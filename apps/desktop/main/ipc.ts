import { ipcMain } from 'electron'
import type { FlorinQueries } from '@florin/core/types'
import { getSyncStatus } from './scheduler'

export function registerIpcHandlers(
  queries: FlorinQueries,
  syncAllFn: () => Promise<void>,
) {
  ipcMain.handle('tray:get-data', async () => {
    const [netWorth, burn, topExpenses, reviewCount] = await Promise.all([
      queries.getNetWorth(),
      queries.getMonthBurn(),
      queries.getTopExpenses(3, 7),
      queries.countNeedsReview(),
    ])
    return { netWorth, burn, topExpenses, reviewCount }
  })

  ipcMain.handle('tray:sync-all', async () => {
    try {
      await syncAllFn()
      return { success: true }
    } catch (error: unknown) {
      const message = error instanceof Error ? error.message : 'unknown error'
      return { success: false, error: message }
    }
  })

  ipcMain.handle('tray:sync-status', () => {
    return getSyncStatus()
  })
}
