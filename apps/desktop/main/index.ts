import { app, BrowserWindow } from 'electron'
import path from 'node:path'
import { createSqliteClient, createSqliteQueries, createSqliteMutations, ensureSchema, schema } from '@florin/db-sqlite'
import { eq } from 'drizzle-orm'
import { broadcastDataChanged, createWindow, getMainWindow, showMainWindow, syncPinCookie } from './window'
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
// Scoped strictly to the local loopback origin: any other host with a bad
// certificate must still fail closed, otherwise the renderer could silently
// load MITM'd external content.
app.on('certificate-error', (event, _webContents, url, _error, _cert, callback) => {
  if (url.startsWith('https://127.0.0.1:') || url.startsWith('https://localhost:')) {
    event.preventDefault()
    callback(true)
  } else {
    callback(false)
  }
})

/**
 * fetch()-shaped helper for calling our own local HTTPS server (self-signed
 * cert). TLS verification is disabled for THIS request only — never set
 * NODE_TLS_REJECT_UNAUTHORIZED globally: the Next.js server runs in this
 * same process, and the global flag would strip certificate checks from its
 * outbound calls to the Enable Banking API too.
 */
async function localFetch(
  url: string,
  options: { method?: string } = {},
): Promise<{ ok: boolean; status: number; statusText: string; json: () => Promise<unknown> }> {
  const { request } = await import('node:https')
  return new Promise((resolve, reject) => {
    const req = request(
      url,
      { method: options.method ?? 'GET', rejectUnauthorized: false },
      (res) => {
        const chunks: Buffer[] = []
        res.on('data', (c: Buffer) => chunks.push(c))
        res.on('end', () => {
          const body = Buffer.concat(chunks).toString('utf8')
          const status = res.statusCode ?? 0
          resolve({
            ok: status >= 200 && status < 300,
            status,
            statusText: res.statusMessage ?? '',
            json: async () => JSON.parse(body),
          })
        })
      },
    )
    req.on('error', reject)
    req.end()
  })
}

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
    const res = await localFetch(
      `https://127.0.0.1:${port}/api/banking/sync?trigger=${trigger}`,
      { method: 'POST' },
    )
    if (!res.ok) {
      const body = (await res.json().catch(() => ({ error: res.statusText }))) as {
        error?: string
      }
      throw new Error(body.error ?? `Sync failed (${res.status})`)
    }
  }

  // Refresh security price quotes by delegating to the Next.js API route over
  // localhost HTTPS — same rationale as syncAllFn: the pricing client, drizzle,
  // and @/ aliases only resolve inside the Next.js server context. No-op when
  // the user hasn't enabled a price provider. Fully fire-and-forget: an offline
  // machine or disabled provider must never throw out of the scheduler.
  const refreshPricesFn = async () => {
    try {
      await localFetch(`https://127.0.0.1:${port}/api/pricing/refresh`, { method: 'POST' })
    } catch {
      // offline or server not ready — ignore
    }
  }

  // Register IPC handlers for tray widget data fetching and sync
  registerIpcHandlers(db, queries, mutations, () => syncAllFn('manual'))

  // Start background bank sync scheduler (2min warmup, then every 6h).
  // After each sync, tell the main window to re-fetch server data via
  // router.refresh() (preserves client state), refresh the tray widget, and
  // refresh portfolio price quotes (cheap, fire-and-forget).
  startSyncScheduler(() => syncAllFn('scheduler'), () => {
    broadcastDataChanged('sync')
    const trayWin = getTrayWindow()
    if (trayWin) trayWin.webContents.send('tray:refresh')
    void refreshPricesFn()
  })

  // One-shot warmup refresh so a freshly-opened app shows fresh prices without
  // waiting for the first 6h scheduler tick.
  void refreshPricesFn()
})

app.on('window-all-closed', () => {
  // Don't quit — keep running in tray (tray added in Task 9)
})

// macOS: closing the window only HIDES it (see window.ts), and after an
// auto-update relaunch the app can come back with no visible window. Re-show
// (and focus) the main window whenever the app is activated — Dock click, ⌘-Tab,
// or the post-update relaunch — so it never sits "running but invisible".
app.on('activate', () => {
  showMainWindow()
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
