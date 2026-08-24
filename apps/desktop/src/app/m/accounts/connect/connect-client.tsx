'use client'

import { ConnectScreen } from '@florin/core/components/v2/screens/connect'
import type { V2Bank, V2Connection } from '@florin/core/components/v2/screens/connect'

/**
 * Thin client boundary so the desktop build can hand the bank's SCA URL to the
 * system browser. Electron's renderer must not navigate itself to a bank login
 * page — the bank fingerprints the browser, and the user would lose the app.
 */
export function ConnectClient(props: {
  configured: boolean
  banks: V2Bank[]
  connections: V2Connection[]
  country: string
  onStart: (bank: V2Bank) => Promise<{ success: boolean; url?: string; error?: string }>
  onSync: (connectionId: string) => Promise<void>
}) {
  return (
    <ConnectScreen
      {...props}
      openUrl={(url) => {
        if (window.florin?.openExternal) window.florin.openExternal(url)
        else window.location.assign(url)
      }}
    />
  )
}
