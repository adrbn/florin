'use client'

import { useState } from 'react'
import { ChevronDown, ChevronRight } from 'lucide-react'
import type { PlanGroup as PlanGroupModel } from '@florin/core/types'
import { formatCurrency } from '@florin/core/lib/format'
import { PlanCategoryRow } from './PlanCategoryRow'

interface PlanGroupProps {
  group: PlanGroupModel
  currency: string
  onAssignedChange: (categoryId: string, amount: number) => void
}

// currency is unused — formatCurrency reads from setCurrencyConfig singleton
export function PlanGroup({ group, currency: _currency, onAssignedChange }: PlanGroupProps) {
  const [open, setOpen] = useState(true)

  return (
    <section className="border-b border-border">
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        className="w-full flex items-center justify-between gap-3 px-4 py-2 bg-muted/30 hover:bg-muted/60 text-left"
      >
        <div className="flex items-center gap-1 min-w-0">
          {open ? <ChevronDown size={16} /> : <ChevronRight size={16} />}
          <span className="font-semibold text-sm truncate">{group.name}</span>
          {group.overspentCount > 0 ? (
            <span className="ml-2 inline-flex items-center justify-center text-xs font-medium bg-red-500/15 text-red-500 border border-red-500/30 rounded-full px-2 py-0.5">
              {group.overspentCount} overspent
            </span>
          ) : null}
        </div>
        <div className="flex items-center gap-6 text-xs text-muted-foreground shrink-0">
          <div className="text-right">
            <div className="uppercase tracking-wide">Assigned</div>
            <div className="font-semibold text-foreground">
              {formatCurrency(group.assigned)}
            </div>
          </div>
          <div className="text-right">
            <div className="uppercase tracking-wide">Available</div>
            <div className={`font-semibold ${group.available < 0 ? 'text-red-500' : 'text-foreground'}`}>
              {formatCurrency(group.available)}
            </div>
          </div>
        </div>
      </button>
      {open ? (
        <div>
          {group.categories.map((c) => (
            <PlanCategoryRow
              key={c.id}
              category={c}
              currency={_currency}
              onAssignedChange={onAssignedChange}
            />
          ))}
        </div>
      ) : null}
    </section>
  )
}
