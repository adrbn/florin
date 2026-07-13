import { autoUpdater } from 'electron-updater'
import { BrowserWindow, ipcMain } from 'electron'

export type UpdateState = 'available' | 'downloading' | 'ready'
export type UpdateStatus = { state: UpdateState; version: string } | null

// Last-known update status, kept so the renderer can pull it on mount (the
// initial check often fires before any window subscribes) as well as receive
// live pushes. `null` = no update / not checked yet.
let current: UpdateStatus = null

function setStatus(next: UpdateStatus) {
  current = next
  for (const w of BrowserWindow.getAllWindows()) {
    w.webContents.send('update:status', current)
  }
}

export function initAutoUpdater() {
  try {
    autoUpdater.autoDownload = true
    autoUpdater.autoInstallOnAppQuit = true

    autoUpdater.on('update-available', (info) => {
      setStatus({ state: 'available', version: info.version })
    })

    // Fires repeatedly while downloading — only broadcast the one-time
    // available → downloading transition, not every progress tick.
    autoUpdater.on('download-progress', () => {
      if (current?.state === 'available') {
        setStatus({ state: 'downloading', version: current.version })
      }
    })

    autoUpdater.on('update-downloaded', (info) => {
      setStatus({ state: 'ready', version: info.version })
    })

    autoUpdater.on('error', (err) => {
      // Non-fatal (no network, no release, unsigned dev build…) but log it —
      // a swallowed signing/config error is otherwise undiagnosable.
      console.warn('[updater] update check failed:', err?.message ?? err)
    })

    ipcMain.handle('update:get-status', () => current)
    ipcMain.on('install-update', () => {
      autoUpdater.quitAndInstall()
    })

    autoUpdater.checkForUpdates().catch(() => {})
    setInterval(() => autoUpdater.checkForUpdates().catch(() => {}), 6 * 60 * 60 * 1000)
  } catch {
    // Auto-updater may fail in unsigned/dev builds — not critical
  }
}
