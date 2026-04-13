'use client'

import { useState, useEffect } from 'react'
import { Download } from 'lucide-react'

declare global {
  interface Window {
    florin?: {
      onUpdateDownloaded?: (cb: (version: string) => void) => void
      installUpdate?: () => void
    }
  }
}

export function UpdateBanner() {
  const [version, setVersion] = useState<string | null>(null)

  useEffect(() => {
    window.florin?.onUpdateDownloaded?.((v) => setVersion(v))
  }, [])

  if (!version) return null

  return (
    <div className="fixed bottom-4 right-4 z-50 flex items-center gap-3 rounded-lg border border-border bg-popover px-4 py-3 text-sm shadow-lg animate-in slide-in-from-bottom-4">
      <Download className="h-4 w-4 text-emerald-500" />
      <span>
        Florin <strong>{version}</strong> is ready
      </span>
      <button
        type="button"
        onClick={() => window.florin?.installUpdate?.()}
        className="rounded-md bg-emerald-600 px-3 py-1 text-xs font-medium text-white hover:bg-emerald-700"
      >
        Restart & Update
      </button>
      <button
        type="button"
        onClick={() => setVersion(null)}
        className="text-muted-foreground hover:text-foreground"
      >
        Later
      </button>
    </div>
  )
}
