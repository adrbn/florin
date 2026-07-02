import { autoUpdater } from 'electron-updater'
import { BrowserWindow, ipcMain } from 'electron'

export function initAutoUpdater() {
  try {
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

    autoUpdater.on('error', (err) => {
      // Non-fatal (no network, no release, unsigned dev build…) but log it —
      // a swallowed signing/config error is otherwise undiagnosable.
      console.warn('[updater] update check failed:', err?.message ?? err)
    })

    ipcMain.on('install-update', () => {
      autoUpdater.quitAndInstall()
    })

    autoUpdater.checkForUpdates().catch(() => {})
    setInterval(() => autoUpdater.checkForUpdates().catch(() => {}), 6 * 60 * 60 * 1000)
  } catch {
    // Auto-updater may fail in unsigned/dev builds — not critical
  }
}
