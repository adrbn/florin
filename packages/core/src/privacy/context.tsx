'use client'
import { createContext, useCallback, useContext, useEffect, useState } from 'react'

const STORAGE_KEY = 'florin-privacy-mode'
const EVENT = 'florin-privacy-change'

interface PrivacyContextValue {
  hidden: boolean
  toggle: () => void
  set: (v: boolean) => void
}

const PrivacyContext = createContext<PrivacyContextValue>({
  hidden: false,
  toggle: () => {},
  set: () => {},
})

export function PrivacyProvider({ children }: { children: React.ReactNode }) {
  const [hidden, setHidden] = useState(false)

  useEffect(() => {
    try {
      const raw = window.localStorage.getItem(STORAGE_KEY)
      if (raw === '1') setHidden(true)
    } catch {}
    const onChange = (e: Event) => {
      const detail = (e as CustomEvent<boolean>).detail
      setHidden(Boolean(detail))
    }
    window.addEventListener(EVENT, onChange)
    return () => window.removeEventListener(EVENT, onChange)
  }, [])

  const set = useCallback((v: boolean) => {
    setHidden(v)
    try {
      window.localStorage.setItem(STORAGE_KEY, v ? '1' : '0')
    } catch {}
    window.dispatchEvent(new CustomEvent(EVENT, { detail: v }))
  }, [])

  const toggle = useCallback(() => set(!hidden), [hidden, set])

  return (
    <PrivacyContext.Provider value={{ hidden, toggle, set }}>{children}</PrivacyContext.Provider>
  )
}

export function usePrivacy() {
  return useContext(PrivacyContext)
}

/**
 * Mask a formatted currency/number string by replacing digit runs with bullets
 * while preserving the currency symbol, separators, and sign. Keeps the width
 * roughly stable so layouts don't jump when toggling.
 */
export function maskAmount(formatted: string): string {
  return formatted.replace(/[\d]+/g, (run) => '•'.repeat(Math.max(run.length, 1)))
}
