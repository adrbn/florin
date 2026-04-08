'use client'

import { type ReactNode, useEffect, useRef, useState } from 'react'

export interface CategoryOption {
  id: string
  name: string
  emoji: string | null
  groupName: string
}

interface CategoryPickerProps {
  options: ReadonlyArray<CategoryOption>
  onPick: (categoryId: string | null) => void
  trigger: ReactNode
  disabled?: boolean
  /** Whether the popover should expose a "clear category" option. */
  showClear?: boolean
  /** Align the popover to the right edge of the trigger instead of the left. */
  align?: 'left' | 'right'
}

/**
 * Reusable filterable category picker popover.
 *
 * Callers provide the trigger (a button, a chip, a plain span) and a
 * callback; the component handles open/close, filter, click-outside, and
 * rendering of the grouped options. Decoupled from any specific
 * transaction id so bulk actions and single-row pickers can share it.
 */
export function CategoryPicker({
  options,
  onPick,
  trigger,
  disabled = false,
  showClear = false,
  align = 'left',
}: CategoryPickerProps) {
  const [open, setOpen] = useState(false)
  const [filter, setFilter] = useState('')
  const ref = useRef<HTMLDivElement>(null)

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

  const handlePick = (categoryId: string | null) => {
    setOpen(false)
    setFilter('')
    onPick(categoryId)
  }

  const query = filter.trim().toLowerCase()
  const filtered =
    query === ''
      ? options
      : options.filter(
          (o) =>
            o.name.toLowerCase().includes(query) || o.groupName.toLowerCase().includes(query),
        )

  return (
    <div ref={ref} className="relative inline-block">
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        disabled={disabled}
        className="inline-flex items-center gap-1 text-left disabled:opacity-50"
      >
        {trigger}
      </button>
      {open && (
        <div
          className={`absolute ${
            align === 'right' ? 'right-0' : 'left-0'
          } top-full z-50 mt-1 w-64 rounded-md border border-border bg-popover p-1 shadow-lg`}
        >
          <input
            type="text"
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
            placeholder="Filter…"
            autoFocus
            className="mb-1 w-full rounded-md border border-input bg-background px-2 py-1 text-xs"
          />
          <div className="max-h-64 overflow-y-auto">
            {showClear && (
              <button
                type="button"
                onClick={() => handlePick(null)}
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
                  onClick={() => handlePick(o.id)}
                  className="block w-full rounded-md px-2 py-1 text-left text-xs hover:bg-muted"
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
