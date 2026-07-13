'use client'

import { useEffect, useState } from 'react'

/**
 * Tracks the desktop auto-updater status exposed over the preload bridge. Pulls
 * the current status once on mount — the startup check can fire before this
 * component exists — then subscribes to live pushes. Returns `null` while the
 * app is current or `window.florin` is unavailable (e.g. dev in a browser).
 */
export function useUpdateStatus(): UpdateStatus {
  const [status, setStatus] = useState<UpdateStatus>(null)

  useEffect(() => {
    let active = true
    window.florin
      ?.getUpdateStatus?.()
      .then((s) => {
        if (active) setStatus(s ?? null)
      })
      .catch(() => {})
    const off = window.florin?.onUpdateStatus?.((s) => setStatus(s ?? null))
    return () => {
      active = false
      off?.()
    }
  }, [])

  return status
}
