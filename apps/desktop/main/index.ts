import { app, BrowserWindow } from 'electron'
import path from 'node:path'
import { createWindow, getMainWindow } from './window'

// Extend app to track quitting state
declare module 'electron' {
  interface App {
    isQuitting?: boolean
  }
}

app.whenReady().then(async () => {
  // Start Next.js custom server
  const port = await startNextServer()

  // Create main window
  createWindow(port)
})

app.on('window-all-closed', () => {
  // Don't quit — keep running in tray (tray added in Task 9)
})

app.on('before-quit', () => {
  app.isQuitting = true
})

async function startNextServer(): Promise<number> {
  const next = (await import('next')).default
  const nextApp = next({ dev: process.env.NODE_ENV !== 'production', dir: path.join(__dirname, '..') })
  const handle = nextApp.getRequestHandler()
  await nextApp.prepare()

  const { createServer } = await import('node:http')
  return new Promise((resolve) => {
    const server = createServer((req, res) => handle(req, res))
    server.listen(0, '127.0.0.1', () => {
      const addr = server.address()
      const port = typeof addr === 'object' ? addr!.port : 3001
      resolve(port)
    })
  })
}
