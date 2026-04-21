import { BrowserWindow, app, session, shell } from 'electron'
import path from 'node:path'

let mainWindow: BrowserWindow | null = null
let mainPort: number = 0

/**
 * Treat any URL not pointing at our local Next.js server as external and
 * hand it off to the OS default browser.
 */
function isExternalUrl(url: string, port: number): boolean {
  if (!url) return false
  if (url.startsWith('about:') || url === 'about:blank') return false
  try {
    const parsed = new URL(url)
    if (parsed.hostname === '127.0.0.1' && parsed.port === String(port)) return false
    if (parsed.protocol === 'file:') return false
    return parsed.protocol === 'http:' || parsed.protocol === 'https:'
  } catch {
    return false
  }
}

export function createWindow(port: number) {
  mainPort = port
  mainWindow = new BrowserWindow({
    title: 'Florin',
    width: 1280,
    height: 800,
    minWidth: 900,
    minHeight: 600,
    titleBarStyle: 'hiddenInset',
    trafficLightPosition: { x: 16, y: 16 },
    webPreferences: {
      preload: path.join(__dirname, 'preload.cjs'),
      nodeIntegration: false,
      contextIsolation: true,
    },
  })

  mainWindow.loadURL(`https://127.0.0.1:${port}`)

  // Route target=_blank and window.open to the OS default browser.
  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    if (isExternalUrl(url, port)) {
      shell.openExternal(url)
      return { action: 'deny' }
    }
    return { action: 'allow' }
  })

  // Catch plain <a href> clicks that would navigate the frame away.
  mainWindow.webContents.on('will-navigate', (event, url) => {
    if (isExternalUrl(url, port)) {
      event.preventDefault()
      shell.openExternal(url)
    }
  })

  // Keep the window title as "Florin" regardless of page <title> changes
  mainWindow.on('page-title-updated', (event) => {
    event.preventDefault()
  })

  // When the window regains focus (e.g. coming back from the system browser
  // after completing bank auth, or switching spaces), nudge the renderer to
  // re-fetch server data. This is a cheap router.refresh() on the client —
  // NOT a full webContents.reload() — so client state (scroll, dropdowns,
  // in-progress forms) is preserved.
  mainWindow.on('focus', () => {
    broadcastDataChanged('focus')
  })

  mainWindow.on('close', (event) => {
    if (!app.isQuitting) {
      event.preventDefault()
      mainWindow?.hide()
    }
  })
}

/**
 * Sync PIN-enabled cookie from database state. Called on startup so the
 * middleware knows whether to enforce PIN protection even on fresh sessions.
 */
export async function syncPinCookie(pinEnabled: boolean) {
  const url = `https://127.0.0.1:${mainPort}`
  const ses = session.defaultSession
  if (pinEnabled) {
    await ses.cookies.set({
      url,
      name: 'florin-pin-enabled',
      value: '1',
      httpOnly: true,
      sameSite: 'strict',
    })
  } else {
    await ses.cookies.remove(url, 'florin-pin-enabled').catch(() => {})
    await ses.cookies.remove(url, 'florin-pin-ok').catch(() => {})
  }
}

export function getMainWindow() {
  return mainWindow
}

export function showMainWindow() {
  if (mainWindow) {
    mainWindow.show()
    mainWindow.focus()
  }
}

/**
 * Notify the main-window renderer that server-side data has changed so it can
 * re-fetch via `router.refresh()`. This avoids blowing away client state with
 * a full `webContents.reload()` — scroll positions, open dropdowns, and
 * pending gesture interactions all survive.
 */
export function broadcastDataChanged(reason: string) {
  if (!mainWindow || mainWindow.isDestroyed()) return
  mainWindow.webContents.send('florin:data-changed', reason)
}
