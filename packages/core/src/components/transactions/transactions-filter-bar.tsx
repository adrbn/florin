'use client'

import { Search, SlidersHorizontal, X } from 'lucide-react'
import type { Route } from 'next'
import { usePathname, useRouter, useSearchParams } from 'next/navigation'
import { useEffect, useMemo, useState, useTransition } from 'react'
import { Button } from '../ui/button'
import { Input } from '../ui/input'

export interface FilterBarAccountOption {
  id: string
  name: string
}

export interface FilterBarCategoryOption {
  id: string
  name: string
  emoji: string | null
  groupName: string
}

interface TransactionsFilterBarProps {
  accounts: ReadonlyArray<FilterBarAccountOption>
  categories: ReadonlyArray<FilterBarCategoryOption>
}

// Debounce keystrokes in the payee search box so every character doesn't
// refire the server action. 250ms is short enough to feel "live" and long
// enough to avoid typing-induced thrashing.
const SEARCH_DEBOUNCE_MS = 250

/**
 * Filter bar that drives the Transactions page. Every control writes its
 * value back into the URL's searchParams via router.replace(), so reloading
 * or sharing the URL reproduces the same view — and the server component on
 * the other side reads those params to build the `listTransactions` call.
 *
 * The bar is intentionally dense: one row of primary controls (search,
 * account, category, direction, clear) + an "Advanced" toggle that reveals
 * date range and amount range inputs. Everything is uncontrolled once the
 * user starts typing (we seed from searchParams on first render only) so
 * server-driven resets (e.g. Clear filter button) don't fight with local
 * state.
 */
export function TransactionsFilterBar({ accounts, categories }: TransactionsFilterBarProps) {
  const router = useRouter()
  const pathname = usePathname()
  const searchParams = useSearchParams()
  const [, startNavTransition] = useTransition()

  // Read current filter values out of the URL. We use these as the "seed"
  // for local form state so the inputs start in sync with the page that
  // the server just rendered.
  const currentQ = searchParams.get('q') ?? ''
  const currentAccount = searchParams.get('accountId') ?? ''
  const currentCategory = searchParams.get('categoryId') ?? ''
  const currentDirection = searchParams.get('direction') ?? 'all'
  const currentFrom = searchParams.get('from') ?? ''
  const currentTo = searchParams.get('to') ?? ''
  const currentMin = searchParams.get('minAmount') ?? ''
  const currentMax = searchParams.get('maxAmount') ?? ''
  const currentExcludeTransfers = searchParams.get('excludeTransfers') === '1'

  // Local state for the text field only — we debounce its writes to the URL.
  // Every other control is pushed immediately on change because selecting an
  // account/category doesn't thrash.
  const [search, setSearch] = useState(currentQ)
  useEffect(() => {
    setSearch(currentQ)
  }, [currentQ])

  const [advancedOpen, setAdvancedOpen] = useState(() => {
    return Boolean(currentFrom || currentTo || currentMin || currentMax || currentExcludeTransfers)
  })

  // Helper: rebuild the URL with the given patch applied. Empty string values
  // remove the param entirely so the URL stays clean when a filter is cleared.
  const pushWithPatch = (patch: Record<string, string | null>) => {
    const next = new URLSearchParams(searchParams.toString())
    for (const [key, value] of Object.entries(patch)) {
      if (value === null || value === '') next.delete(key)
      else next.set(key, value)
    }
    const query = next.toString()
    const href = (query ? `${pathname}?${query}` : pathname) as Route
    startNavTransition(() => router.replace(href, { scroll: false }))
  }

  // Debounced search commit. The local `search` state updates on every
  // keystroke (instant feedback in the input) but the URL only gets rewritten
  // after the user pauses for SEARCH_DEBOUNCE_MS.
  useEffect(() => {
    if (search === currentQ) return
    const handle = setTimeout(() => {
      pushWithPatch({ q: search || null })
    }, SEARCH_DEBOUNCE_MS)
    return () => clearTimeout(handle)
    // Intentionally omit pushWithPatch/currentQ: we want a single debounced
    // write per pause, not cascaded effects when other params change.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [search])

  // Group categories by group name for a nicer dropdown.
  const categoriesByGroup = useMemo(() => {
    const map = new Map<string, FilterBarCategoryOption[]>()
    for (const c of categories) {
      const group = c.groupName ?? 'Other'
      const list = map.get(group) ?? []
      list.push(c)
      map.set(group, list)
    }
    return Array.from(map.entries()).sort(([a], [b]) => a.localeCompare(b))
  }, [categories])

  const hasAnyFilter =
    currentQ !== '' ||
    currentAccount !== '' ||
    currentCategory !== '' ||
    currentDirection !== 'all' ||
    currentFrom !== '' ||
    currentTo !== '' ||
    currentMin !== '' ||
    currentMax !== '' ||
    currentExcludeTransfers

  const clearAll = () => {
    setSearch('')
    startNavTransition(() => router.replace(pathname as Route, { scroll: false }))
  }

  return (
    <div className="space-y-2">
      {/* Primary row */}
      <div className="flex flex-wrap items-center gap-2 rounded-lg border border-border bg-card px-3 py-2 text-sm">
        {/* Search */}
        <div className="relative flex min-w-0 flex-1 items-center">
          <Search className="pointer-events-none absolute left-2 h-4 w-4 text-muted-foreground" />
          <Input
            type="search"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search payee…"
            className="h-8 pl-8"
            aria-label="Search payee"
          />
        </div>

        {/* Account picker */}
        <select
          value={currentAccount}
          onChange={(e) => pushWithPatch({ accountId: e.target.value || null })}
          className="h-8 rounded-md border border-border bg-background px-2 text-xs"
          aria-label="Filter by account"
        >
          <option value="">All accounts</option>
          {accounts.map((a) => (
            <option key={a.id} value={a.id}>
              {a.name}
            </option>
          ))}
        </select>

        {/* Category picker (with uncategorized) */}
        <select
          value={currentCategory}
          onChange={(e) => pushWithPatch({ categoryId: e.target.value || null })}
          className="h-8 rounded-md border border-border bg-background px-2 text-xs"
          aria-label="Filter by category"
        >
          <option value="">All categories</option>
          <option value="none">— Uncategorized —</option>
          {categoriesByGroup.map(([group, cats]) => (
            <optgroup key={group} label={group}>
              {cats.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.emoji ? `${c.emoji} ` : ''}
                  {c.name}
                </option>
              ))}
            </optgroup>
          ))}
        </select>

        {/* Direction toggle */}
        <select
          value={currentDirection}
          onChange={(e) => pushWithPatch({ direction: e.target.value === 'all' ? null : e.target.value })}
          className="h-8 rounded-md border border-border bg-background px-2 text-xs"
          aria-label="Filter by direction"
        >
          <option value="all">All</option>
          <option value="expense">Expenses</option>
          <option value="income">Income</option>
        </select>

        {/* Advanced toggle */}
        <Button
          type="button"
          variant={advancedOpen ? 'default' : 'outline'}
          size="sm"
          className="h-8"
          onClick={() => setAdvancedOpen((v) => !v)}
        >
          <SlidersHorizontal className="mr-1 h-3.5 w-3.5" />
          Advanced
        </Button>

        {hasAnyFilter && (
          <Button
            type="button"
            variant="ghost"
            size="sm"
            className="h-8 text-muted-foreground hover:text-foreground"
            onClick={clearAll}
          >
            <X className="mr-1 h-3.5 w-3.5" />
            Clear
          </Button>
        )}
      </div>

      {/* Advanced row */}
      {advancedOpen && (
        <div className="grid gap-2 rounded-lg border border-border/80 bg-muted/20 px-3 py-2 text-xs md:grid-cols-[auto_auto_auto_auto_auto_1fr]">
          <label className="flex items-center gap-1">
            <span className="text-muted-foreground">From</span>
            <Input
              type="date"
              value={currentFrom}
              onChange={(e) => pushWithPatch({ from: e.target.value || null })}
              className="h-7 w-[140px]"
              aria-label="Filter from date"
            />
          </label>
          <label className="flex items-center gap-1">
            <span className="text-muted-foreground">To</span>
            <Input
              type="date"
              value={currentTo}
              onChange={(e) => pushWithPatch({ to: e.target.value || null })}
              className="h-7 w-[140px]"
              aria-label="Filter to date"
            />
          </label>
          <label className="flex items-center gap-1">
            <span className="text-muted-foreground">Min €</span>
            <Input
              type="number"
              step="0.01"
              value={currentMin}
              onChange={(e) => pushWithPatch({ minAmount: e.target.value || null })}
              placeholder="e.g. -136"
              className="h-7 w-[100px]"
              aria-label="Minimum amount"
            />
          </label>
          <label className="flex items-center gap-1">
            <span className="text-muted-foreground">Max €</span>
            <Input
              type="number"
              step="0.01"
              value={currentMax}
              onChange={(e) => pushWithPatch({ maxAmount: e.target.value || null })}
              placeholder="e.g. -135"
              className="h-7 w-[100px]"
              aria-label="Maximum amount"
            />
          </label>
          <label className="flex items-center gap-1 text-muted-foreground">
            <input
              type="checkbox"
              checked={currentExcludeTransfers}
              onChange={(e) => pushWithPatch({ excludeTransfers: e.target.checked ? '1' : null })}
              className="h-3.5 w-3.5"
            />
            Exclude transfers
          </label>
        </div>
      )}
    </div>
  )
}
