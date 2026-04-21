'use client'

import { useEffect, useRef } from 'react'
import { useRouter } from 'next/navigation'

/**
 * Listens for `florin:data-changed` IPC signals from the main process and
 * triggers a Next.js `router.refresh()` so server components re-render with
 * fresh data. Unlike `window.location.reload()` or Electron's
 * `webContents.reload()`, this preserves client state (scroll position,
 * controlled inputs, open dropdowns) — the React tree just re-reconciles
 * against the new server payload.
 *
 * Debounced by ~500ms so bursts (e.g. focus right after a scheduled sync)
 * collapse into a single refresh.
 */
export function DataRefresher() {
  const router = useRouter()
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  useEffect(() => {
    const bridge = window.florin
    if (!bridge?.onDataChanged) return

    const unsubscribe = bridge.onDataChanged(() => {
      if (timerRef.current) clearTimeout(timerRef.current)
      timerRef.current = setTimeout(() => {
        router.refresh()
      }, 500)
    })

    return () => {
      if (timerRef.current) clearTimeout(timerRef.current)
      unsubscribe?.()
    }
  }, [router])

  return null
}
