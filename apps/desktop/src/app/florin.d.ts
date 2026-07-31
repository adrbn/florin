/** Global type for the Electron preload bridge exposed as `window.florin`. */
declare global {
  /** Auto-updater status pushed from the main process. `null` = app is current. */
  type UpdateStatus =
    | { state: 'available' | 'downloading' | 'ready'; version: string; percent?: number }
    | null

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
      getUpdateStatus: () => Promise<UpdateStatus>
      onUpdateStatus: (cb: (status: UpdateStatus) => void) => () => void
      installUpdate: () => void
      // File picker for PEM import
      importPem: () => Promise<string | null>
      // Generate an RSA key pair in-app (no terminal). Stores the private key
      // and returns its path + the public key PEM to upload to Enable Banking.
      generateEbKey: () => Promise<{ keyPath: string; publicKey: string }>
      // Open URL in system browser
      openExternal: (url: string) => void
    }
  }
}

export {}
