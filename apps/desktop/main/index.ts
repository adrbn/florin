import { app, BrowserWindow } from 'electron'
import path from 'node:path'
import { createSqliteClient, createSqliteQueries } from '@florin/db-sqlite'
import { createWindow, getMainWindow } from './window'
import { setupTray } from './tray'
import { registerIpcHandlers } from './ipc'
import { startSyncScheduler, stopSyncScheduler } from './scheduler'

// Extend app to track quitting state
declare module 'electron' {
  interface App {
    isQuitting?: boolean
  }
}

// Resolve the SQLite database path. In production Electron stores user data at
// ~/Library/Application Support/Florin (macOS). During development we fall back
// to the working directory.
const DB_PATH = path.join(app.getPath('userData'), 'florin.db')

// Set the env var so the Next.js server-side db client (src/db/client.ts) uses
// the same database file as the Electron main process.
process.env.FLORIN_DB_PATH = DB_PATH

app.whenReady().then(async () => {
  // Initialize SQLite database — createSqliteClient enables WAL mode and
  // foreign keys automatically. The schema tables are created lazily by
  // drizzle-kit push (dev) or pre-built migrations (production).
  const db = createSqliteClient(DB_PATH)
  const queries = createSqliteQueries(db)

  // Start Next.js custom server
  const port = await startNextServer()

  // Create main window
  createWindow(port)

  // Set up menu bar tray widget
  setupTray(port)

  // Create a sync function that delegates to the Next.js server-side module.
  // We dynamically import so the module resolves after Next.js has prepared
  // and the FLORIN_DB_PATH env var is visible to the server-side code.
  const syncAllFn = async () => {
    const { syncAllConnections } = await import(
      '../src/server/banking/sync-all'
    )
    await syncAllConnections()
  }

  // Register IPC handlers for tray widget data fetching and sync
  registerIpcHandlers(queries, syncAllFn)

  // Start background bank sync scheduler (2min warmup, then every 6h)
  startSyncScheduler(syncAllFn)
})

app.on('window-all-closed', () => {
  // Don't quit — keep running in tray (tray added in Task 9)
})

app.on('before-quit', () => {
  app.isQuitting = true
  stopSyncScheduler()
})

async function startNextServer(): Promise<number> {
  const next = (await import('next')).default
  const nextApp = next({ dev: process.env.NODE_ENV !== 'production', dir: path.join(__dirname, '..') })
  const handle = nextApp.getRequestHandler()
  await nextApp.prepare()

  const { createServer } = await import('node:http')
  return new Promise((resolve) => {
    const server = createServer((req, res) => handle(req, res))
    server.listen(0, '127.0.0.1', () => {
      const addr = server.address()
      const port = typeof addr === 'object' ? addr!.port : 3001
      resolve(port)
    })
  })
}
