'use client'

import { useEffect, useRef, useState } from 'react'
import type { PlanCategory } from '@florin/core/types'
import { formatCurrency } from '@florin/core/lib/format'

interface PlanCategoryRowProps {
  category: PlanCategory
  currency: string
  onAssignedChange: (categoryId: string, amount: number) => void
}

export function PlanCategoryRow({ category, currency: _currency, onAssignedChange }: PlanCategoryRowProps) {
  const [draft, setDraft] = useState<string>(category.assigned.toString())
  const skipCommitRef = useRef(false)

  useEffect(() => {
    setDraft(category.assigned.toString())
  }, [category.assigned])

  const commit = () => {
    if (skipCommitRef.current) {
      skipCommitRef.current = false
      return
    }
    const parsed = Number(draft.replace(',', '.'))
    if (Number.isFinite(parsed) && parsed >= 0 && parsed !== category.assigned) {
      onAssignedChange(category.id, parsed)
    } else {
      setDraft(category.assigned.toString())
    }
  }

  const available = category.available
  // currency is unused — formatCurrency reads from setCurrencyConfig singleton
  const pillClass = available < 0
    ? 'bg-red-500/15 text-red-500 border-red-500/30'
    : available === 0
      ? 'bg-muted text-muted-foreground border-muted'
      : 'bg-green-500/15 text-green-500 border-green-500/30'

  return (
    <div className="flex items-center justify-between gap-3 border-b border-border px-4 py-2.5">
      <div className="flex items-center gap-2 min-w-0">
        {category.emoji ? <span className="text-lg shrink-0">{category.emoji}</span> : null}
        <span className="truncate text-sm">{category.name}</span>
      </div>
      <div className="flex items-center gap-3 shrink-0">
        <input
          type="text"
          inputMode="decimal"
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onBlur={commit}
          onKeyDown={(e) => {
            if (e.key === 'Enter') (e.target as HTMLInputElement).blur()
            if (e.key === 'Escape') {
              skipCommitRef.current = true
              setDraft(category.assigned.toString())
              ;(e.target as HTMLInputElement).blur()
            }
          }}
          className="w-24 text-right text-sm bg-transparent border-b border-transparent focus:border-border focus:outline-none px-1"
          aria-label={`Assigned for ${category.name}`}
        />
        <span
          className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium border w-28 justify-center ${pillClass}`}
          data-testid={`available-${category.id}`}
        >
          {formatCurrency(available)}
        </span>
      </div>
    </div>
  )
}
