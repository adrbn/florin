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

  // ⌘H / Ctrl+H toggles privacy mode. On desktop, the Electron main process
  // intercepts ⌘H before macOS's native "Hide Application" via
  // before-input-event and forwards an IPC message (window.florin.onTogglePrivacy).
  // On web, we listen directly on keydown — browsers generally let us intercept
  // ⌘H except inside their own reserved shortcuts (Chrome's ⌘H opens History;
  // where that fires first, the user can still use the sidebar toggle button).
  useEffect(() => {
    const onKeyDown = (e: KeyboardEvent) => {
      if (e.key.toLowerCase() !== 'h') return
      if (!(e.metaKey || e.ctrlKey)) return
      if (e.shiftKey || e.altKey) return
      // Skip if focus is inside an editable field — ⌘H in inputs should not
      // be hijacked from the browser's native behaviour (though most browsers
      // ignore it there anyway).
      const target = e.target as HTMLElement | null
      if (
        target &&
        (target.tagName === 'INPUT' ||
          target.tagName === 'TEXTAREA' ||
          target.isContentEditable)
      ) {
        return
      }
      e.preventDefault()
      toggle()
    }
    window.addEventListener('keydown', onKeyDown)

    // Desktop: subscribe to IPC-forwarded toggle so the keystroke works even
    // when macOS consumes ⌘H at the menu layer.
    type FlorinBridge = { onTogglePrivacy?: (cb: () => void) => (() => void) | void }
    const bridge = (window as unknown as { florin?: FlorinBridge }).florin
    const unsubscribe = bridge?.onTogglePrivacy?.(() => toggle())

    return () => {
      window.removeEventListener('keydown', onKeyDown)
      if (typeof unsubscribe === 'function') unsubscribe()
    }
  }, [toggle])

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
