'use client'

import { useMemo, useState, useTransition } from 'react'
import { Check, Search } from 'lucide-react'
import { useRouter } from 'next/navigation'
import { useV2T } from '../../i18n/context'
import { Sheet } from '../../primitives/sheet'
import { cn } from '../../../../lib/utils'
import type { V2Category } from '../../types'

/**
 * Category picker used by Activity and Review.
 *
 * A native <select> with 60 options is unusable on a phone; this is a filtered
 * list grouped by group name, with the search box autofocused only on desktop
 * — autofocusing it on mobile throws the keyboard up over the list the user
 * came to look at.
 */
export function CategoryPickerSheet({
  open,
  onClose,
  categories,
  currentId,
  onPick,
  title,
}: {
  open: boolean
  onClose: () => void
  categories: V2Category[]
  currentId?: string | null
  onPick: (categoryId: string | null) => Promise<unknown>
  title?: string
}) {
  const t = useV2T()
  const router = useRouter()
  const [query, setQuery] = useState('')
  const [pending, start] = useTransition()
  const [busyId, setBusyId] = useState<string | null>(null)

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase()
    const list = q
      ? categories.filter(
          (c) => c.name.toLowerCase().includes(q) || c.groupName.toLowerCase().includes(q),
        )
      : categories
    const byGroup = new Map<string, V2Category[]>()
    for (const c of list) {
      const arr = byGroup.get(c.groupName)
      if (arr) arr.push(c)
      else byGroup.set(c.groupName, [c])
    }
    return [...byGroup.entries()]
  }, [categories, query])

  const choose = (id: string | null) => {
    setBusyId(id ?? '__none__')
    start(async () => {
      await onPick(id)
      setBusyId(null)
      router.refresh()
      onClose()
    })
  }

  return (
    <Sheet
      open={open}
      onClose={onClose}
      title={title ?? t('v2.review.pickCategory', 'Pick a category')}
    >
      <div className="v2-gutter flex flex-col gap-3 pt-1">
        <label className="relative block">
          <Search
            aria-hidden
            className="pointer-events-none absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-[var(--v2-text-3)]"
          />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder={t('v2.common.search', 'Search')}
            aria-label={t('v2.common.search', 'Search')}
            className="v2-input pl-10"
          />
        </label>

        <button
          type="button"
          disabled={pending}
          onClick={() => choose(null)}
          className={cn(
            'v2-row v2-row-tap rounded-[var(--v2-r-md)] px-3',
            currentId == null && 'bg-[var(--v2-accent-soft)]',
          )}
        >
          <span className="v2-title flex-1">{t('v2.common.uncategorized', 'Uncategorized')}</span>
          {busyId === '__none__' && <span className="v2-micro">…</span>}
          {currentId == null && <Check className="h-4 w-4 text-[var(--v2-accent-text)]" />}
        </button>
      </div>

      <div className="flex flex-col gap-4 pt-3">
        {filtered.map(([group, items]) => (
          <section key={group} className="flex flex-col">
            <h3 className="v2-eyebrow v2-gutter pb-1.5">{group}</h3>
            {items.map((c) => {
              const active = c.id === currentId
              return (
                <button
                  key={c.id}
                  type="button"
                  disabled={pending}
                  onClick={() => choose(c.id)}
                  className={cn('v2-row v2-row-tap', active && 'bg-[var(--v2-accent-soft)]')}
                >
                  <span className="v2-bubble h-9 w-9 rounded-xl text-[17px]">
                    {c.emoji ?? c.name.slice(0, 1).toUpperCase()}
                  </span>
                  <span className="v2-title flex-1 truncate text-left">{c.name}</span>
                  {busyId === c.id && <span className="v2-micro">…</span>}
                  {active && <Check className="h-4 w-4 text-[var(--v2-accent-text)]" />}
                </button>
              )
            })}
          </section>
        ))}
      </div>
    </Sheet>
  )
}
