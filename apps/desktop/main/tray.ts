import { Tray, BrowserWindow, nativeImage, ipcMain } from 'electron'
import path from 'node:path'
import { getMainWindow, showMainWindow } from './window'

let tray: Tray | null = null
let trayWindow: BrowserWindow | null = null

export function setupTray(_port: number) {
  const iconPath = path.join(__dirname, '../assets/tray-iconTemplate.png')
  let icon: Electron.NativeImage
  try {
    icon = nativeImage.createFromPath(iconPath)
  } catch {
    icon = nativeImage.createEmpty()
  }

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
          trayWindow?.showInactive()
          trayWindow?.webContents.send('tray:refresh')
        })
        .catch(() => {
          positionTrayWindow()
          trayWindow?.showInactive()
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
  const trayBounds = tray.getBounds()
  const windowBounds = trayWindow.getBounds()
  const x = Math.round(trayBounds.x + trayBounds.width / 2 - windowBounds.width / 2)
  const y = Math.round(trayBounds.y + trayBounds.height)
  trayWindow.setPosition(x, y, false)
}

export function getTrayWindow() {
  return trayWindow
}
