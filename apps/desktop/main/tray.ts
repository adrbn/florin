import { Tray, BrowserWindow, nativeImage, ipcMain, screen } from 'electron'
import path from 'node:path'
import { getMainWindow, showMainWindow } from './window'

let tray: Tray | null = null
let trayWindow: BrowserWindow | null = null

export function setupTray(_port: number) {
  const iconPath = path.join(__dirname, '../assets/tray-iconTemplate.png')
  // createFromPath returns an empty image on failure (it doesn't throw), and an
  // empty image hands macOS an invisible tray — then tray.getBounds() returns
  // {0,0,0,0} and the popup ends up parked at the top-left of the screen.
  // Resize to the menu-bar height explicitly and mark as template so macOS
  // renders it in the right place and invert-colors in dark menu bars.
  const raw = nativeImage.createFromPath(iconPath)
  const icon = raw.isEmpty() ? nativeImage.createEmpty() : raw.resize({ width: 16, height: 16 })
  icon.setTemplateImage(true)

  tray = new Tray(icon)
  tray.setToolTip('Florin')

  trayWindow = new BrowserWindow({
    width: 380,
    height: 10,
    show: false,
    frame: false,
    resizable: false,
    movable: false,
    alwaysOnTop: true,
    skipTaskbar: true,
    transparent: false,
    hasShadow: true,
    roundedCorners: true,
    backgroundColor: '#0f1117',
    // Panel type prevents the app from activating (stealing focus from other
    // apps) when the tray popup is shown — it floats above everything like a
    // proper menu bar widget.
    type: 'panel',
    // Keep the popup on the current space only — prevent it from reappearing
    // after a Mission Control / space switch animation.
    visibleOnAllWorkspaces: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.cjs'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  })

  trayWindow.loadFile(path.join(__dirname, '../tray-ui/index.html'))

  // Auto-size window to match popup content height
  trayWindow.webContents.on('did-finish-load', () => {
    trayWindow?.webContents
      .executeJavaScript('document.querySelector(".popup").offsetHeight')
      .then((h: number) => {
        if (h > 0) trayWindow?.setSize(380, h)
      })
      .catch(() => {})
  })

  trayWindow.on('blur', () => {
    trayWindow?.hide()
  })

  tray.on('click', () => {
    if (trayWindow?.isVisible()) {
      trayWindow.hide()
    } else {
      // Re-measure content height before showing (form may have toggled)
      trayWindow?.webContents
        .executeJavaScript('document.querySelector(".popup").offsetHeight')
        .then((h: number) => {
          if (h > 0) trayWindow?.setSize(380, h)
          positionTrayWindow()
          trayWindow?.show()
          trayWindow?.webContents.send('tray:refresh')
        })
        .catch(() => {
          positionTrayWindow()
          trayWindow?.show()
          trayWindow?.webContents.send('tray:refresh')
        })
    }
  })

  // IPC: open main dashboard window
  ipcMain.on('open-dashboard', () => {
    showMainWindow()
    trayWindow?.hide()
  })

  // IPC: resize tray window when content changes (e.g. form toggle)
  ipcMain.on('tray:resize', (_event, height: number) => {
    if (trayWindow && height > 0) {
      trayWindow.setSize(380, height)
      positionTrayWindow()
    }
  })

  // IPC: reload dashboard after tray changes data
  ipcMain.on('tray:data-changed', () => {
    const main = getMainWindow()
    if (main) {
      main.webContents.reload()
    }
  })
}

function positionTrayWindow() {
  if (!tray || !trayWindow) return
  const windowBounds = trayWindow.getBounds()

  // Prefer the cursor position at click time over tray.getBounds(): on
  // multi-display setups and when the tray icon is pushed into the overflow
  // menu (Bartender, Stage Manager, small notch), getBounds() returns either
  // zeros or stale values from the wrong display — and the popup drifts to
  // the top-left of the primary screen. The cursor is always on the display
  // that owns the menu bar the user just clicked.
  const cursor = screen.getCursorScreenPoint()
  const activeDisplay = screen.getDisplayNearestPoint(cursor)
  const display = activeDisplay.workArea

  const trayBounds = tray.getBounds()
  const hasSensibleBounds =
    trayBounds.width > 0 &&
    trayBounds.height > 0 &&
    trayBounds.x >= display.x &&
    trayBounds.x + trayBounds.width <= display.x + display.width

  const anchorX = hasSensibleBounds ? trayBounds.x + trayBounds.width / 2 : cursor.x
  const anchorY = hasSensibleBounds ? trayBounds.y + trayBounds.height : display.y + 4

  const x = Math.round(Math.min(
    display.x + display.width - windowBounds.width - 4,
    Math.max(display.x + 4, anchorX - windowBounds.width / 2),
  ))
  const y = Math.round(anchorY)
  trayWindow.setPosition(x, y, false)
}

export function getTrayWindow() {
  return trayWindow
}
