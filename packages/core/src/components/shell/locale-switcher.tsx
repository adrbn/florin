'use client'

import { useEffect, useRef, useState, useTransition } from 'react'
import { Languages } from 'lucide-react'
import { useLocale } from '../../i18n/context'

const LOCALES: Array<{ code: 'en' | 'fr'; label: string }> = [
  { code: 'fr', label: 'FR' },
  { code: 'en', label: 'EN' },
]

interface LocaleSwitcherProps {
  endpoint?: string
  variant?: 'inline' | 'compact'
}

// Reads the active locale from the React context — seeded server-side from
// the user's cookie — and writes updates via an app-specific endpoint
// (default `/api/locale`). Using context instead of `document.documentElement.lang`
// guarantees the highlighted button matches the rendered content, even during
// the short window before hydration has reconciled the <html> attribute.
//
// `variant="compact"` renders a single Languages icon button that pops a
// small menu — used in the mobile top bar where screen space is tight.
export function LocaleSwitcher({ endpoint = '/api/locale', variant = 'inline' }: LocaleSwitcherProps) {
  const [pending, startTransition] = useTransition()
  const [open, setOpen] = useState(false)
  const containerRef = useRef<HTMLDivElement>(null)
  const ctxLocale = useLocale()
  const current: 'en' | 'fr' = ctxLocale.toLowerCase().startsWith('fr') ? 'fr' : 'en'

  useEffect(() => {
    if (variant !== 'compact' || !open) return
    const onDocClick = (e: MouseEvent) => {
      if (!containerRef.current?.contains(e.target as Node)) setOpen(false)
    }
    document.addEventListener('mousedown', onDocClick)
    return () => document.removeEventListener('mousedown', onDocClick)
  }, [variant, open])

  const onPick = (locale: 'en' | 'fr') => {
    if (locale === current) {
      setOpen(false)
      return
    }
    startTransition(async () => {
      await fetch(endpoint, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ locale }),
      })
      window.location.reload()
    })
  }

  if (variant === 'compact') {
    return (
      <div ref={containerRef} className="relative">
        <button
          type="button"
          onClick={() => setOpen((v) => !v)}
          aria-haspopup="menu"
          aria-expanded={open}
          aria-label={`Language: ${current.toUpperCase()}`}
          className="flex items-center gap-1 rounded-md px-2 py-1 text-[11px] text-sidebar-foreground/70 transition-colors hover:bg-sidebar-accent hover:text-sidebar-accent-foreground"
        >
          <Languages className="h-3.5 w-3.5" />
          <span className="font-semibold uppercase">{current}</span>
        </button>
        {open && (
          <div
            role="menu"
            className="absolute right-0 z-40 mt-1 flex flex-col overflow-hidden rounded-md border border-border bg-popover text-popover-foreground shadow-md"
          >
            {LOCALES.map((l) => {
              const active = l.code === current
              return (
                <button
                  key={l.code}
                  type="button"
                  role="menuitemradio"
                  aria-checked={active}
                  disabled={pending}
                  onClick={() => onPick(l.code)}
                  className={
                    'px-3 py-1.5 text-left text-xs font-medium transition-colors ' +
                    (active ? 'bg-accent text-accent-foreground' : 'hover:bg-accent/60')
                  }
                >
                  {l.label}
                </button>
              )
            })}
          </div>
        )}
      </div>
    )
  }

  return (
    <div className="flex w-full items-center gap-3 rounded-md px-3 py-2 text-sm text-sidebar-foreground/70">
      <Languages className="h-4 w-4" />
      <div className="flex items-center gap-1">
        {LOCALES.map((l) => {
          const active = l.code === current
          return (
            <button
              key={l.code}
              type="button"
              onClick={() => onPick(l.code)}
              disabled={pending}
              aria-pressed={active}
              className={
                'rounded px-1.5 py-0.5 text-xs font-medium transition-colors ' +
                (active
                  ? 'bg-sidebar-accent text-sidebar-accent-foreground'
                  : 'text-sidebar-foreground/60 hover:text-sidebar-foreground')
              }
            >
              {l.label}
            </button>
          )
        })}
      </div>
    </div>
  )
}
