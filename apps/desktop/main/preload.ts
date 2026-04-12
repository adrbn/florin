import { contextBridge, ipcRenderer } from 'electron'

contextBridge.exposeInMainWorld('florin', {
  getTrayData: () => ipcRenderer.invoke('tray:get-data'),
  syncAll: () => ipcRenderer.invoke('tray:sync-all'),
  getSyncStatus: () => ipcRenderer.invoke('tray:sync-status'),
  openDashboard: () => ipcRenderer.send('open-dashboard'),
  openAddTransaction: () => ipcRenderer.send('open-add-transaction'),
  onRefresh: (cb: () => void) => {
    ipcRenderer.on('tray:refresh', cb)
  },
})
