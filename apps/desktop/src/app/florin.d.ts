/** Global type for the Electron preload bridge exposed as `window.florin`. */
declare global {
  interface Window {
    florin?: {
      // Tray IPC
      getTrayData: () => Promise<unknown>
      syncAll: () => Promise<unknown>
      getSyncStatus: () => Promise<unknown>
      listAccounts: () => Promise<unknown>
      listCategories: () => Promise<unknown>
      addTransaction: (input: {
        accountId: string
        amount: number
        payee: string
        categoryId?: string
      }) => Promise<unknown>
      openDashboard: () => void
      quitApp: () => void
      dataChanged: () => void
      resizeWindow: (height: number) => void
      onRefresh: (cb: () => void) => void
      onDataChanged: (cb: (reason: string) => void) => () => void
      // Auto-updater
      onUpdateDownloaded: (cb: (version: string) => void) => void
      installUpdate: () => void
      // File picker for PEM import
      importPem: () => Promise<string | null>
      // Open URL in system browser
      openExternal: (url: string) => void
    }
  }
}

export {}
