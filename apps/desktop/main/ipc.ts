import { app, dialog, ipcMain, shell } from 'electron'
import { copyFile } from 'node:fs/promises'
import path from 'node:path'
import { eq } from 'drizzle-orm'
import type { FlorinQueries, FlorinMutations } from '@florin/core/types'
import { createT, normalizeLocale } from '@florin/core/i18n'
import { type SqliteDB, schema } from '@florin/db-sqlite'
import { getSyncStatus } from './scheduler'

const TRAY_STRING_KEYS = [
  'tray.synced',
  'tray.syncing',
  'tray.error',
  'tray.netWorth',
  'tray.monthlyBurn',
  'tray.recentExpenses',
  'tray.loading',
  'tray.noRecentExpenses',
  'tray.quickAdd',
  'tray.payeePlaceholder',
  'tray.amountPlaceholder',
  'tray.loadingAccounts',
  'tray.noCategory',
  'tray.addButton',
  'tray.syncNow',
  'tray.addTransaction',
  'tray.openDashboard',
  'tray.quit',
  'tray.unknown',
  'tray.fillAllFields',
  'tray.invalidAmount',
  'tray.added',
  'tray.failed',
  'tray.failedToAdd',
] as const

function readUserLocale(db: SqliteDB): 'en' | 'fr' {
  try {
    const row = db
      .select({ value: schema.settings.value })
      .from(schema.settings)
      .where(eq(schema.settings.key, 'user_locale'))
      .get()
    return normalizeLocale(row?.value)
  } catch {
    return 'en'
  }
}

export function registerIpcHandlers(
  db: SqliteDB,
  queries: FlorinQueries,
  mutations: FlorinMutations,
  syncAllFn: () => Promise<void>,
) {
  ipcMain.handle('tray:get-locale-strings', () => {
    const t = createT(readUserLocale(db))
    const strings: Record<string, string> = {}
    for (const key of TRAY_STRING_KEYS) strings[key] = t(key)
    return strings
  })

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

  // File picker for PEM import — copies the selected file into userData and
  // returns the destination path so the renderer can save it to settings.
  ipcMain.handle('dialog:import-pem', async () => {
    const result = await dialog.showOpenDialog({
      title: 'Select RSA Private Key (.pem)',
      filters: [
        { name: 'PEM files', extensions: ['pem', 'key'] },
        { name: 'All files', extensions: ['*'] },
      ],
      properties: ['openFile'],
    })
    if (result.canceled || result.filePaths.length === 0) return null
    const src = result.filePaths[0]!
    const dest = path.join(app.getPath('userData'), 'private.pem')
    await copyFile(src, dest)
    return dest
  })

  // Open a URL in the system browser (for bank SCA redirects)
  ipcMain.on('shell:open-external', (_event, url: string) => {
    shell.openExternal(url)
  })

  ipcMain.on('quit-app', () => {
    app.isQuitting = true
    app.quit()
  })
}
