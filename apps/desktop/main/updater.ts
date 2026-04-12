import { autoUpdater } from 'electron-updater'
import { BrowserWindow } from 'electron'

export function initAutoUpdater() {
  autoUpdater.autoDownload = true
  autoUpdater.autoInstallOnAppQuit = true

  autoUpdater.on('update-available', (info) => {
    BrowserWindow.getAllWindows().forEach((w) =>
      w.webContents.send('update-available', info.version)
    )
  })

  autoUpdater.on('update-downloaded', (info) => {
    BrowserWindow.getAllWindows().forEach((w) =>
      w.webContents.send('update-downloaded', info.version)
    )
  })

  autoUpdater.checkForUpdates().catch(() => {})
  setInterval(() => autoUpdater.checkForUpdates().catch(() => {}), 6 * 60 * 60 * 1000)
}
