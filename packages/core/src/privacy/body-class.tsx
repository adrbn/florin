'use client'
import { useEffect } from 'react'
import { usePrivacy } from './context'

// Sync privacy state with a class on <html>. Pair with a global CSS rule
// (see each app's globals.css) that blurs elements tagged with
// `data-amount` when the class is present.
export function PrivacyBodyClass() {
  const { hidden } = usePrivacy()
  useEffect(() => {
    const el = document.documentElement
    if (hidden) el.classList.add('privacy-hidden')
    else el.classList.remove('privacy-hidden')
  }, [hidden])
  return null
}
