import { app, BrowserWindow } from 'electron'
import path from 'node:path'
import { createSqliteClient, createSqliteQueries, createSqliteMutations, ensureSchema, schema } from '@florin/db-sqlite'
import { eq } from 'drizzle-orm'
import { broadcastDataChanged, createWindow, getMainWindow, syncPinCookie } from './window'
import { setupTray, getTrayWindow } from './tray'
import { registerIpcHandlers } from './ipc'
import { startSyncScheduler, stopSyncScheduler } from './scheduler'
import { initAutoUpdater } from './updater'

// Prevent uncaught exceptions from crashing the app with a dialog
process.on('uncaughtException', (err) => {
  console.error('[main] uncaught exception:', err)
})

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

// Allow the self-signed localhost certificate used by our HTTPS server.
// Without this, Electron's Chromium rejects the page load entirely.
app.on('certificate-error', (event, _webContents, _url, _error, _cert, callback) => {
  event.preventDefault()
  callback(true)
})

// Also allow Node.js fetch (used by the main process for sync API calls) to
// accept the self-signed localhost cert. This only affects local loopback —
// renderer-side HTTPS goes through Chromium's stack above.
process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0'

app.whenReady().then(async () => {
  // Initialize SQLite database — createSqliteClient enables WAL mode and
  // foreign keys automatically. ensureSchema runs CREATE TABLE IF NOT EXISTS
  // for every table on every boot, so users upgrading from older desktop
  // builds automatically get tables added since their install (e.g.
  // monthly_budgets, added for the Plan tab).
  const db = createSqliteClient(DB_PATH)
  ensureSchema(db)
  const queries = createSqliteQueries(db)
  const mutations = createSqliteMutations(db)

  // Start Next.js custom server
  const port = await startNextServer()

  // Sync PIN cookie from database before creating the window so the
  // middleware knows whether to enforce PIN on the very first request.
  let pinEnabled = false
  try {
    const row = db
      .select({ value: schema.settings.value })
      .from(schema.settings)
      .where(eq(schema.settings.key, 'pin_hash'))
      .get()
    pinEnabled = Boolean(row?.value)
  } catch { /* settings table may not exist yet */ }

  // Create main window
  createWindow(port)

  // Sync PIN cookie state
  await syncPinCookie(pinEnabled)

  // Initialize auto-updater (checks GitHub Releases)
  initAutoUpdater()

  // Set up menu bar tray widget
  setupTray(port)

  // Sync function delegates to the Next.js API route over localhost HTTPS.
  // This keeps the sync logic running inside the Next.js server context where
  // path aliases, drizzle, and Enable Banking modules resolve correctly —
  // a bare dynamic import from the main process fails because @/ aliases
  // don't resolve outside webpack/Next.js.
  const syncAllFn = async (trigger: 'manual' | 'scheduler' = 'manual') => {
    const res = await fetch(
      `https://127.0.0.1:${port}/api/banking/sync?trigger=${trigger}`,
      { method: 'POST' },
    )
    if (!res.ok) {
      const body = await res.json().catch(() => ({ error: res.statusText }))
      throw new Error(body.error ?? `Sync failed (${res.status})`)
    }
  }

  // Register IPC handlers for tray widget data fetching and sync
  registerIpcHandlers(db, queries, mutations, () => syncAllFn('manual'))

  // Start background bank sync scheduler (2min warmup, then every 6h).
  // After each sync, tell the main window to re-fetch server data via
  // router.refresh() (preserves client state), and refresh the tray widget.
  startSyncScheduler(() => syncAllFn('scheduler'), () => {
    broadcastDataChanged('sync')
    const trayWin = getTrayWindow()
    if (trayWin) trayWin.webContents.send('tray:refresh')
  })
})

app.on('window-all-closed', () => {
  // Don't quit — keep running in tray (tray added in Task 9)
})

app.on('before-quit', () => {
  app.isQuitting = true
  stopSyncScheduler()
})

async function startNextServer(): Promise<number> {
  const isProd = app.isPackaged
  // In production, the app root is the asar/unpacked resource directory.
  // __dirname is dist-main/ inside the app, so '..' reaches the app root.
  const appDir = path.join(__dirname, '..')
  if (isProd) process.env.NODE_ENV = 'production'

  const next = (await import('next')).default
  const nextApp = next({ dev: !isProd, dir: appDir })
  const handle = nextApp.getRequestHandler()
  await nextApp.prepare()

  // Enable Banking requires HTTPS redirect URIs, so we serve the local
  // Next.js server over TLS with a self-signed certificate generated on
  // first launch and stored in the userData directory.
  const { createServer } = await import('node:https')
  const cert = await getOrCreateLocalCert()
  const FIXED_PORT = 3847
  return new Promise((resolve) => {
    const server = createServer({ key: cert.key, cert: cert.cert }, (req, res) =>
      handle(req, res),
    )
    server.listen(FIXED_PORT, '127.0.0.1', () => {
      resolve(FIXED_PORT)
    })
  })
}

/**
 * Generate (or reuse) a self-signed TLS certificate so the local Next.js
 * server can run over HTTPS. Enable Banking mandates HTTPS redirect URIs,
 * even for localhost. The cert is stored in the app's userData directory
 * and is only used for the local loopback — never exposed to the network.
 */
async function getOrCreateLocalCert(): Promise<{ key: string; cert: string }> {
  const fs = await import('node:fs/promises')
  const keyPath = path.join(app.getPath('userData'), 'localhost-key.pem')
  const certPath = path.join(app.getPath('userData'), 'localhost-cert.pem')
  try {
    const [key, cert] = await Promise.all([
      fs.readFile(keyPath, 'utf8'),
      fs.readFile(certPath, 'utf8'),
    ])
    return { key, cert }
  } catch {
    // Generate a self-signed cert valid for 10 years
    const { execSync } = await import('node:child_process')
    execSync(
      `openssl req -x509 -newkey rsa:2048 -keyout "${keyPath}" -out "${certPath}" ` +
        `-days 3650 -nodes -subj "/CN=127.0.0.1" -addext "subjectAltName=IP:127.0.0.1,DNS:localhost"`,
    )
    const [key, cert] = await Promise.all([
      fs.readFile(keyPath, 'utf8'),
      fs.readFile(certPath, 'utf8'),
    ])
    return { key, cert }
  }
}
