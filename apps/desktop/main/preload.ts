import { contextBridge, ipcRenderer } from 'electron'

contextBridge.exposeInMainWorld('florin', {
  getLocaleStrings: () =>
    ipcRenderer.invoke('tray:get-locale-strings') as Promise<Record<string, string>>,
  getTrayData: () => ipcRenderer.invoke('tray:get-data'),
  syncAll: () => ipcRenderer.invoke('tray:sync-all'),
  getSyncStatus: () => ipcRenderer.invoke('tray:sync-status'),
  listAccounts: () => ipcRenderer.invoke('tray:list-accounts'),
  listCategories: () => ipcRenderer.invoke('tray:list-categories'),
  addTransaction: (input: { accountId: string; amount: number; payee: string; categoryId?: string }) =>
    ipcRenderer.invoke('tray:add-transaction', input),
  openDashboard: () => ipcRenderer.send('open-dashboard'),
  quitApp: () => ipcRenderer.send('quit-app'),
  dataChanged: () => ipcRenderer.send('tray:data-changed'),
  resizeWindow: (height: number) => ipcRenderer.send('tray:resize', height),
  onRefresh: (cb: () => void) => {
    ipcRenderer.on('tray:refresh', cb)
  },
  onUpdateDownloaded: (cb: (version: string) => void) => {
    ipcRenderer.on('update-downloaded', (_event, version) => cb(version))
  },
  installUpdate: () => ipcRenderer.send('install-update'),
  importPem: () => ipcRenderer.invoke('dialog:import-pem') as Promise<string | null>,
  openExternal: (url: string) => ipcRenderer.send('shell:open-external', url),
})
