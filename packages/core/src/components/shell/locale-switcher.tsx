'use client'

import { useTransition } from 'react'
import { Languages } from 'lucide-react'

const LOCALES: Array<{ code: 'en' | 'fr'; label: string }> = [
  { code: 'fr', label: 'FR' },
  { code: 'en', label: 'EN' },
]

// Reads and writes the locale via an app-specific endpoint (default `/api/locale`)
// so web and desktop can share this component while each controls its own
// cookie/storage. On success the page is reloaded so server components pick up
// the new locale.
export function LocaleSwitcher({ endpoint = '/api/locale' }: { endpoint?: string }) {
  const [pending, startTransition] = useTransition()

  const current = readLocaleFromDocument()

  const onPick = (locale: 'en' | 'fr') => {
    if (locale === current) return
    startTransition(async () => {
      await fetch(endpoint, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ locale }),
      })
      window.location.reload()
    })
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

function readLocaleFromDocument(): 'en' | 'fr' {
  if (typeof document === 'undefined') return 'en'
  const lang = document.documentElement.lang?.toLowerCase() ?? ''
  return lang.startsWith('fr') ? 'fr' : 'en'
}
