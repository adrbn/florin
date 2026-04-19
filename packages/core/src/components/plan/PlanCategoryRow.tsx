'use client'

import { useEffect, useRef, useState } from 'react'
import type { PlanCategory } from '@florin/core/types'
import { formatCurrency } from '@florin/core/lib/format'

interface PlanCategoryRowProps {
  category: PlanCategory
  currency: string
  onAssignedChange: (categoryId: string, amount: number) => void
  onShowTransactions: (categoryId: string) => void
}

const assignedToDraft = (value: number): string => (value === 0 ? '' : value.toString())

export function PlanCategoryRow({
  category,
  currency: _currency,
  onAssignedChange,
  onShowTransactions,
}: PlanCategoryRowProps) {
  const [draft, setDraft] = useState<string>(assignedToDraft(category.assigned))
  const [isFocused, setIsFocused] = useState(false)
  const skipCommitRef = useRef(false)

  useEffect(() => {
    setDraft(assignedToDraft(category.assigned))
  }, [category.assigned])

  const commit = () => {
    if (skipCommitRef.current) {
      skipCommitRef.current = false
      return
    }
    const trimmed = draft.trim()
    const parsed = trimmed === '' ? 0 : Number(trimmed.replace(',', '.'))
    if (Number.isFinite(parsed) && parsed >= 0 && parsed !== category.assigned) {
      onAssignedChange(category.id, parsed)
    } else {
      setDraft(assignedToDraft(category.assigned))
    }
  }

  const available = category.available
  const isZero = category.assigned === 0
  // currency is unused — formatCurrency reads from setCurrencyConfig singleton
  const pillClass = available < 0
    ? 'bg-red-500/15 text-red-500 border-red-500/30'
    : available === 0
      ? 'bg-muted text-muted-foreground border-muted'
      : 'bg-green-500/15 text-green-500 border-green-500/30'

  const displayValue = isFocused ? draft : (isZero ? '' : formatCurrency(category.assigned))

  return (
    <div
      className={`relative flex items-center justify-between gap-3 border-b border-border px-4 py-2.5 transition-colors ${
        isFocused ? 'bg-primary/10 ring-1 ring-inset ring-primary/30' : ''
      }`}
    >
      <div className="flex items-center gap-2 min-w-0">
        {category.emoji ? <span className="text-lg shrink-0">{category.emoji}</span> : null}
        <span className="truncate text-sm">{category.name}</span>
      </div>
      <div className="flex items-center gap-3 shrink-0">
        <input
          type="text"
          inputMode="decimal"
          value={displayValue}
          placeholder="0,00 €"
          onChange={(e) => setDraft(e.target.value)}
          onFocus={(e) => {
            setIsFocused(true)
            const target = e.target as HTMLInputElement
            // Select AFTER React commits the draft value (raw number vs formatted string)
            setTimeout(() => target.select(), 0)
          }}
          onBlur={() => {
            setIsFocused(false)
            commit()
          }}
          onKeyDown={(e) => {
            if (e.key === 'Enter') (e.target as HTMLInputElement).blur()
            if (e.key === 'Escape') {
              skipCommitRef.current = true
              setDraft(assignedToDraft(category.assigned))
              ;(e.target as HTMLInputElement).blur()
            }
          }}
          className="w-24 text-right text-sm bg-transparent border-b border-transparent focus:border-border focus:outline-none px-1 placeholder:text-muted-foreground/50"
          aria-label={`Assigned for ${category.name}`}
        />
        <button
          type="button"
          onClick={() => onShowTransactions(category.id)}
          className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium border w-28 justify-center cursor-pointer hover:brightness-110 focus:outline-none focus:ring-2 focus:ring-primary/40 ${pillClass}`}
          data-testid={`available-${category.id}`}
          aria-label={`Show ${category.name} transactions`}
        >
          {formatCurrency(available)}
        </button>
      </div>
    </div>
  )
}
