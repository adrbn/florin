import { BrowserWindow, app, session } from 'electron'

let mainWindow: BrowserWindow | null = null
let mainPort: number = 0

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
      nodeIntegration: false,
      contextIsolation: true,
    },
  })

  mainWindow.loadURL(`https://127.0.0.1:${port}`)

  // Keep the window title as "Florin" regardless of page <title> changes
  mainWindow.on('page-title-updated', (event) => {
    event.preventDefault()
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
