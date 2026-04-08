'use client'

import { useEffect, useRef, useState, useTransition } from 'react'
import { updateTransactionCategory } from '@/server/actions/transactions'

interface CategoryOption {
  id: string
  name: string
  emoji: string | null
  groupName: string
}

interface TransactionCategoryCellProps {
  transactionId: string
  currentCategoryId: string | null
  currentCategoryName: string | null
  currentCategoryEmoji: string | null
  options: ReadonlyArray<CategoryOption>
}

/**
 * Inline category picker for one transaction row.
 *
 * Closed state: shows the current category as a click target.
 * Open state: shows a filterable popover of categories grouped by group.
 *
 * Uses a controlled popover (no portal) to keep things simple — the
 * Transactions table is short enough that overflow clipping isn't an issue.
 */
export function TransactionCategoryCell({
  transactionId,
  currentCategoryId,
  currentCategoryName,
  currentCategoryEmoji,
  options,
}: TransactionCategoryCellProps) {
  const [open, setOpen] = useState(false)
  const [filter, setFilter] = useState('')
  const [pending, startTransition] = useTransition()
  const ref = useRef<HTMLDivElement>(null)
  const filterRef = useRef<HTMLInputElement>(null)

  // Click-outside to close.
  useEffect(() => {
    if (!open) return
    const onClick = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        setOpen(false)
      }
    }
    document.addEventListener('mousedown', onClick)
    return () => document.removeEventListener('mousedown', onClick)
  }, [open])

  // Focus the filter input whenever the popover opens. Manual focus instead
  // of the `autoFocus` attribute so a11y lint is happy — the effect runs
  // only on user intent (click), not on page load.
  useEffect(() => {
    if (open) {
      filterRef.current?.focus()
    }
  }, [open])

  const onPick = (categoryId: string | null) => {
    setOpen(false)
    setFilter('')
    startTransition(async () => {
      await updateTransactionCategory(transactionId, categoryId)
    })
  }

  const filtered = options.filter((o) =>
    filter.trim() === ''
      ? true
      : o.name.toLowerCase().includes(filter.toLowerCase()) ||
        o.groupName.toLowerCase().includes(filter.toLowerCase()),
  )

  return (
    <div ref={ref} className="relative inline-block">
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        disabled={pending}
        className="inline-flex items-center gap-1 rounded-md px-1.5 py-0.5 text-left text-xs hover:bg-muted disabled:opacity-50"
      >
        {currentCategoryName ? (
          <span className="flex items-center gap-1 text-foreground">
            {currentCategoryEmoji && <span aria-hidden>{currentCategoryEmoji}</span>}
            <span>{currentCategoryName}</span>
          </span>
        ) : (
          <span className="italic text-muted-foreground">uncategorized</span>
        )}
        <span className="text-muted-foreground/60">▾</span>
      </button>
      {open && (
        <div className="absolute left-0 top-full z-50 mt-1 w-64 rounded-md border border-border bg-popover p-1 shadow-lg">
          <input
            ref={filterRef}
            type="text"
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
            placeholder="Filter…"
            className="mb-1 w-full rounded-md border border-input bg-background px-2 py-1 text-xs"
          />
          <div className="max-h-64 overflow-y-auto">
            {currentCategoryId && (
              <button
                type="button"
                onClick={() => onPick(null)}
                className="block w-full rounded-md px-2 py-1 text-left text-xs italic text-muted-foreground hover:bg-muted"
              >
                ✕ Clear category
              </button>
            )}
            {filtered.length === 0 ? (
              <p className="px-2 py-1 text-xs text-muted-foreground">No matches.</p>
            ) : (
              filtered.map((o) => (
                <button
                  type="button"
                  key={o.id}
                  onClick={() => onPick(o.id)}
                  className={`block w-full rounded-md px-2 py-1 text-left text-xs hover:bg-muted ${
                    o.id === currentCategoryId ? 'bg-muted font-medium' : ''
                  }`}
                >
                  <span className="flex items-center justify-between gap-2">
                    <span className="flex items-center gap-1.5 truncate">
                      {o.emoji && <span aria-hidden>{o.emoji}</span>}
                      <span className="truncate text-foreground">{o.name}</span>
                    </span>
                    <span className="text-[10px] text-muted-foreground">{o.groupName}</span>
                  </span>
                </button>
              ))
            )}
          </div>
        </div>
      )}
    </div>
  )
}
