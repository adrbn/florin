'use client'

import { useEffect, useState, useCallback, useRef } from 'react'
import { useRouter } from 'next/navigation'
import { Search, ArrowRight, Wallet, Tag, Receipt } from 'lucide-react'
import { formatCurrencySigned } from '../../lib/format/currency'

const NAV_SHORTCUTS: Record<string, string> = {
  '1': '/',
  '2': '/accounts',
  '3': '/transactions',
  '4': '/reflect',
  '5': '/tools',
  '6': '/categories',
  '7': '/settings',
}

interface PageResult {
  label: string
  href: string
  section: string
}

const PAGE_ITEMS: PageResult[] = [
  { label: 'Dashboard', href: '/', section: 'Pages' },
  { label: 'Accounts', href: '/accounts', section: 'Pages' },
  { label: 'Transactions', href: '/transactions', section: 'Pages' },
  { label: 'Reflect', href: '/reflect', section: 'Pages' },
  { label: 'Tools', href: '/tools', section: 'Pages' },
  { label: 'Categories', href: '/categories', section: 'Pages' },
  { label: 'Settings', href: '/settings', section: 'Pages' },
  { label: 'About', href: '/about', section: 'Pages' },
]

interface SearchTransaction {
  id: string
  payee: string
  amount: string | number
  date: string
  accountId: string
}

interface SearchAccount {
  id: string
  name: string
  kind: string
}

interface SearchCategory {
  id: string
  name: string
  emoji: string | null
  groupName: string
}

interface SearchResults {
  transactions: SearchTransaction[]
  accounts: SearchAccount[]
  categories: SearchCategory[]
}

/**
 * Global keyboard shortcut + command palette. Mounted once in the dashboard
 * shell on both desktop and web. Cmd/Ctrl+K opens the palette; Cmd/Ctrl+N
 * creates a transaction; Cmd/Ctrl+1..7 navigates between primary pages.
 *
 * The palette fetches from `/api/search?q=` which each app mounts against
 * its own database. Hard navigation (`window.location.href`) keeps things
 * simple and bypasses RSC diffing overhead, which helps on Electron and
 * costs little on web.
 */
export function KeyboardShortcuts() {
  const router = useRouter()
  const [searchOpen, setSearchOpen] = useState(false)
  const [searchQuery, setSearchQuery] = useState('')
  const [results, setResults] = useState<SearchResults | null>(null)
  const [selectedIndex, setSelectedIndex] = useState(0)
  const [loading, setLoading] = useState(false)
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  const allItems: Array<{
    label: string
    sublabel?: string
    href: string
    section: string
    icon?: string
  }> = []

  if (searchQuery.trim().length < 2) {
    PAGE_ITEMS.forEach((p) => allItems.push(p))
  } else {
    const matchingPages = PAGE_ITEMS.filter((p) =>
      p.label.toLowerCase().includes(searchQuery.toLowerCase()),
    )
    matchingPages.forEach((p) => allItems.push(p))

    if (results) {
      results.accounts.forEach((a) =>
        allItems.push({
          label: a.name,
          sublabel: a.kind,
          href: `/accounts/${a.id}`,
          section: 'Accounts',
          icon: 'wallet',
        }),
      )
      results.transactions.forEach((t) =>
        allItems.push({
          label: t.payee || '(no payee)',
          sublabel: formatCurrencySigned(t.amount),
          href: `/transactions?highlight=${t.id}`,
          section: 'Transactions',
          icon: 'receipt',
        }),
      )
      results.categories.forEach((c) =>
        allItems.push({
          label: `${c.emoji ? c.emoji + ' ' : ''}${c.name}`,
          sublabel: c.groupName,
          href: `/transactions?categoryId=${c.id}`,
          section: 'Categories',
          icon: 'tag',
        }),
      )
    }
  }

  useEffect(() => {
    if (!searchOpen) return
    if (searchQuery.trim().length < 2) {
      setResults(null)
      setSelectedIndex(0)
      return
    }

    if (debounceRef.current) clearTimeout(debounceRef.current)
    debounceRef.current = setTimeout(async () => {
      setLoading(true)
      try {
        const res = await fetch(`/api/search?q=${encodeURIComponent(searchQuery.trim())}`)
        if (res.ok) {
          const data = await res.json()
          setResults(data)
          setSelectedIndex(0)
        }
      } finally {
        setLoading(false)
      }
    }, 200)

    return () => {
      if (debounceRef.current) clearTimeout(debounceRef.current)
    }
  }, [searchQuery, searchOpen])

  const navigate = useCallback((href: string) => {
    setSearchOpen(false)
    setSearchQuery('')
    window.location.href = href
  }, [])

  const handleKeyDown = useCallback(
    (e: KeyboardEvent) => {
      const meta = e.metaKey || e.ctrlKey
      const target = e.target as HTMLElement
      const isInput =
        target.tagName === 'INPUT' || target.tagName === 'TEXTAREA' || target.isContentEditable

      if (meta && e.key === 'k') {
        e.preventDefault()
        setSearchOpen((prev) => !prev)
        setSearchQuery('')
        setResults(null)
        setSelectedIndex(0)
        return
      }

      if (meta && e.key === 'n') {
        e.preventDefault()
        router.push('/transactions?action=add' as never)
        return
      }

      if (meta && e.key === ',') {
        e.preventDefault()
        router.push('/settings' as never)
        return
      }

      if (searchOpen && e.key === 'Escape') {
        e.preventDefault()
        setSearchOpen(false)
        return
      }

      if (isInput) return

      if (meta && NAV_SHORTCUTS[e.key]) {
        e.preventDefault()
        router.push(NAV_SHORTCUTS[e.key] as never)
      }
    },
    [router, searchOpen],
  )

  useEffect(() => {
    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [handleKeyDown])

  if (!searchOpen) return null

  const iconFor = (icon?: string) => {
    if (icon === 'wallet') return <Wallet className="h-3.5 w-3.5 text-muted-foreground" />
    if (icon === 'receipt') return <Receipt className="h-3.5 w-3.5 text-muted-foreground" />
    if (icon === 'tag') return <Tag className="h-3.5 w-3.5 text-muted-foreground" />
    return <ArrowRight className="h-3.5 w-3.5 text-muted-foreground" />
  }

  const sections: Record<string, typeof allItems> = {}
  allItems.forEach((item) => {
    if (!sections[item.section]) sections[item.section] = []
    sections[item.section]!.push(item)
  })

  let flatIndex = 0

  return (
    <div
      className="fixed inset-0 z-50 flex items-start justify-center pt-[18vh]"
      onClick={() => setSearchOpen(false)}
    >
      <div className="fixed inset-0 bg-black/50 backdrop-blur-sm" />
      <div
        className="relative w-full max-w-lg overflow-hidden rounded-xl border border-border bg-popover shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center gap-2 border-b border-border px-4">
          <Search className="h-4 w-4 text-muted-foreground" />
          <input
            autoFocus
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'ArrowDown') {
                e.preventDefault()
                setSelectedIndex((i) => Math.min(i + 1, allItems.length - 1))
              } else if (e.key === 'ArrowUp') {
                e.preventDefault()
                setSelectedIndex((i) => Math.max(i - 1, 0))
              } else if (e.key === 'Enter' && allItems.length > 0) {
                e.preventDefault()
                navigate(allItems[selectedIndex]!.href)
              } else if (e.key === 'Escape') {
                setSearchOpen(false)
              }
            }}
            placeholder="Search pages, transactions, accounts, categories..."
            className="flex-1 border-0 bg-transparent py-3 text-sm text-foreground outline-none placeholder:text-muted-foreground"
          />
          {loading && (
            <span className="h-4 w-4 animate-spin rounded-full border-2 border-muted-foreground border-t-transparent" />
          )}
          <kbd className="rounded border border-border bg-muted px-1.5 py-0.5 text-[10px] text-muted-foreground">
            ESC
          </kbd>
        </div>
        <div className="max-h-[360px] overflow-y-auto p-1.5">
          {allItems.length === 0 ? (
            <p className="px-2 py-6 text-center text-sm text-muted-foreground">
              {loading ? 'Searching…' : 'No results found'}
            </p>
          ) : (
            Object.entries(sections).map(([section, items]) => (
              <div key={section}>
                <p className="px-3 pb-1 pt-2 text-[10px] font-medium uppercase tracking-wider text-muted-foreground">
                  {section}
                </p>
                {items.map((item) => {
                  const idx = flatIndex++
                  const isSelected = idx === selectedIndex
                  return (
                    <button
                      key={item.href + item.label}
                      type="button"
                      onMouseEnter={() => setSelectedIndex(idx)}
                      onClick={() => navigate(item.href)}
                      className={`flex w-full cursor-pointer items-center gap-2.5 rounded-lg px-3 py-2 text-sm transition-colors ${
                        isSelected
                          ? 'bg-accent text-accent-foreground'
                          : 'text-foreground hover:bg-accent/50'
                      }`}
                    >
                      {iconFor(item.icon)}
                      <span className="min-w-0 flex-1 truncate text-left">{item.label}</span>
                      {item.sublabel && (
                        <span className="shrink-0 text-xs text-muted-foreground">
                          {item.sublabel}
                        </span>
                      )}
                    </button>
                  )
                })}
              </div>
            ))
          )}
        </div>
        <div className="flex items-center gap-4 border-t border-border px-4 py-2 text-[10px] text-muted-foreground">
          <span>
            <kbd className="rounded border border-border bg-muted px-1 py-0.5">↑↓</kbd> Navigate
          </span>
          <span>
            <kbd className="rounded border border-border bg-muted px-1 py-0.5">↵</kbd> Open
          </span>
          <span>
            <kbd className="rounded border border-border bg-muted px-1 py-0.5">⌘N</kbd> New
            transaction
          </span>
        </div>
      </div>
    </div>
  )
}
