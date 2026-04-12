import { ipcMain } from 'electron'
import type { FlorinQueries } from '@florin/core/types'

export function registerIpcHandlers(queries: FlorinQueries) {
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
    // Placeholder — sync wiring added in Task 11
    return { success: true }
  })
}
