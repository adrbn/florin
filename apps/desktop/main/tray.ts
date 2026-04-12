import { Tray, BrowserWindow, nativeImage, ipcMain } from 'electron'
import path from 'node:path'
import { showMainWindow } from './window'

let tray: Tray | null = null
let trayWindow: BrowserWindow | null = null

export function setupTray(_port: number) {
  // Create a 16x16 template icon for macOS menu bar
  // Template images auto-adapt to dark/light menu bar
  const iconPath = path.join(__dirname, '../assets/tray-iconTemplate.png')
  let icon: Electron.NativeImage
  try {
    icon = nativeImage.createFromPath(iconPath)
  } catch {
    // Fallback: create a simple empty icon if asset not found
    icon = nativeImage.createEmpty()
  }

  tray = new Tray(icon)
  tray.setToolTip('Florin')

  trayWindow = new BrowserWindow({
    width: 320,
    height: 420,
    show: false,
    frame: false,
    resizable: false,
    movable: false,
    alwaysOnTop: true,
    skipTaskbar: true,
    transparent: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  })

  trayWindow.loadFile(path.join(__dirname, '../tray-ui/index.html'))

  // Hide tray window when it loses focus
  trayWindow.on('blur', () => {
    trayWindow?.hide()
  })

  tray.on('click', () => {
    if (trayWindow?.isVisible()) {
      trayWindow.hide()
    } else {
      positionTrayWindow()
      trayWindow?.show()
      trayWindow?.webContents.send('tray:refresh')
    }
  })

  // IPC: open main dashboard window
  ipcMain.on('open-dashboard', () => {
    showMainWindow()
    trayWindow?.hide()
  })

  ipcMain.on('open-add-transaction', () => {
    showMainWindow()
    trayWindow?.hide()
    // Could navigate to add-transaction, but for now just show main window
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
