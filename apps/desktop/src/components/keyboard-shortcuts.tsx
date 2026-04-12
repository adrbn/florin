'use client'

import { useEffect, useState, useCallback } from 'react'
import { useRouter } from 'next/navigation'
import { Command } from 'lucide-react'

/**
 * Global keyboard shortcut handler for the desktop app.
 *
 * Cmd+N  → Navigate to add transaction (opens /transactions?action=add)
 * Cmd+K  → Open quick search overlay
 * Cmd+,  → Navigate to settings
 * Cmd+1..8 → Navigate to sidebar items
 */

const NAV_SHORTCUTS: Record<string, string> = {
  '1': '/',
  '2': '/accounts',
  '3': '/transactions',
  '4': '/reflect',
  '5': '/tools',
  '6': '/categories',
  '7': '/settings',
}

interface SearchResult {
  label: string
  href: string
  section: string
}

const SEARCH_ITEMS: SearchResult[] = [
  { label: 'Dashboard', href: '/', section: 'Pages' },
  { label: 'Accounts', href: '/accounts', section: 'Pages' },
  { label: 'Transactions', href: '/transactions', section: 'Pages' },
  { label: 'Reflect', href: '/reflect', section: 'Pages' },
  { label: 'Tools', href: '/tools', section: 'Pages' },
  { label: 'Categories', href: '/categories', section: 'Pages' },
  { label: 'Settings', href: '/settings', section: 'Pages' },
  { label: 'About', href: '/about', section: 'Pages' },
  { label: 'Add Transaction', href: '/transactions?action=add', section: 'Actions' },
  { label: 'Export Data', href: '/settings', section: 'Actions' },
]

export function KeyboardShortcuts() {
  const router = useRouter()
  const [searchOpen, setSearchOpen] = useState(false)
  const [searchQuery, setSearchQuery] = useState('')

  const handleKeyDown = useCallback(
    (e: KeyboardEvent) => {
      const meta = e.metaKey || e.ctrlKey
      const target = e.target as HTMLElement
      const isInput = target.tagName === 'INPUT' || target.tagName === 'TEXTAREA' || target.isContentEditable

      if (meta && e.key === 'k') {
        e.preventDefault()
        setSearchOpen((prev) => !prev)
        setSearchQuery('')
        return
      }

      if (meta && e.key === 'n') {
        e.preventDefault()
        router.push('/transactions?action=add')
        return
      }

      if (meta && e.key === ',') {
        e.preventDefault()
        router.push('/settings')
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
        router.push(NAV_SHORTCUTS[e.key]!)
      }
    },
    [router, searchOpen],
  )

  useEffect(() => {
    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [handleKeyDown])

  const filteredItems = searchQuery.trim()
    ? SEARCH_ITEMS.filter((item) =>
        item.label.toLowerCase().includes(searchQuery.toLowerCase()),
      )
    : SEARCH_ITEMS

  if (!searchOpen) return null

  return (
    <div
      className="fixed inset-0 z-50 flex items-start justify-center pt-[20vh]"
      onClick={() => setSearchOpen(false)}
    >
      <div className="fixed inset-0 bg-black/50 backdrop-blur-sm" />
      <div
        className="relative w-full max-w-md overflow-hidden rounded-xl border border-border bg-popover shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center gap-2 border-b border-border px-4">
          <Command className="h-4 w-4 text-muted-foreground" />
          <input
            autoFocus
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && filteredItems.length > 0) {
                router.push(filteredItems[0]!.href)
                setSearchOpen(false)
              }
              if (e.key === 'Escape') {
                setSearchOpen(false)
              }
            }}
            placeholder="Search pages and actions..."
            className="flex-1 border-0 bg-transparent py-3 text-sm text-foreground outline-none placeholder:text-muted-foreground"
          />
          <kbd className="rounded border border-border bg-muted px-1.5 py-0.5 text-[10px] text-muted-foreground">
            ESC
          </kbd>
        </div>
        <div className="max-h-[300px] overflow-y-auto p-2">
          {filteredItems.length === 0 ? (
            <p className="px-2 py-4 text-center text-sm text-muted-foreground">No results found</p>
          ) : (
            filteredItems.map((item) => (
              <button
                key={item.href + item.label}
                type="button"
                onClick={() => {
                  router.push(item.href)
                  setSearchOpen(false)
                }}
                className="flex w-full items-center justify-between rounded-md px-3 py-2 text-sm text-foreground hover:bg-accent"
              >
                <span>{item.label}</span>
                <span className="text-xs text-muted-foreground">{item.section}</span>
              </button>
            ))
          )}
        </div>
        <div className="flex items-center gap-4 border-t border-border px-4 py-2 text-[10px] text-muted-foreground">
          <span><kbd className="rounded border border-border bg-muted px-1 py-0.5">⌘N</kbd> New transaction</span>
          <span><kbd className="rounded border border-border bg-muted px-1 py-0.5">⌘K</kbd> Search</span>
          <span><kbd className="rounded border border-border bg-muted px-1 py-0.5">⌘,</kbd> Settings</span>
        </div>
      </div>
    </div>
  )
}
