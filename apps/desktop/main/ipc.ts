import { app, ipcMain } from 'electron'
import type { FlorinQueries, FlorinMutations } from '@florin/core/types'
import { getSyncStatus } from './scheduler'

export function registerIpcHandlers(
  queries: FlorinQueries,
  mutations: FlorinMutations,
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

  ipcMain.handle('tray:list-accounts', async () => {
    const accounts = await queries.listAccounts()
    return accounts.map((a) => ({ id: a.id, name: a.name }))
  })

  ipcMain.handle('tray:list-categories', async () => {
    const cats = await queries.listCategoriesFlat()
    return cats.map((c) => ({ id: c.id, name: c.name, emoji: c.emoji, groupName: c.groupName }))
  })

  ipcMain.handle('tray:add-transaction', async (_event, input: {
    accountId: string
    amount: number
    payee: string
    categoryId?: string
  }) => {
    try {
      const result = await mutations.addTransaction({
        accountId: input.accountId,
        occurredAt: new Date(),
        amount: input.amount,
        payee: input.payee,
        categoryId: input.categoryId || null,
      })
      return result
    } catch (error: unknown) {
      const message = error instanceof Error ? error.message : 'unknown error'
      return { success: false, error: message }
    }
  })

  ipcMain.on('quit-app', () => {
    app.isQuitting = true
    app.quit()
  })
}
