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

// Replace the entire number portion with a fixed placeholder so the digit
// count doesn't leak magnitude. Currency symbol and sign stay visible.
export function maskAmount(formatted: string): string {
  const hasMinus = /^\s*-/.test(formatted)
  const symbol = formatted.match(/[€$£¥]/)?.[0] ?? ''
  const core = '••••'
  if (symbol) {
    return `${hasMinus ? '-' : ''}${core} ${symbol}`.trim()
  }
  return `${hasMinus ? '-' : ''}${core}`
}
