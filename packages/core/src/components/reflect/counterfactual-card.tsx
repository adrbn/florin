'use client'

import { useMemo, useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '../ui/card'
import { formatCurrency } from '../../lib/format/currency'
import type { CategoryShare } from '../../types/index'

interface CounterfactualCardProps {
  /**
   * Spending by category over the same window (days) as the subtitle hints.
   * The caller is responsible for making those numbers consistent.
   */
  categories: ReadonlyArray<CategoryShare>
  /** Number of days the category totals cover — used to extrapolate to a year. */
  windowDays: number
  title: string
  subtitle: string
  suggestion: string
  yearLabel: string
  noDataLabel: string
}

/**
 * Counterfactual savings explorer — "if I stopped X, Y, Z, I'd save $N/yr".
 *
 * Tick the categories you'd be willing to cut; the card extrapolates the
 * selection to a year using the same window the upstream query ran against.
 * This is intentionally naive (straight ratio) rather than modelling
 * seasonality because the point is to motivate, not to forecast.
 */
export function CounterfactualCard({
  categories,
  windowDays,
  title,
  subtitle,
  suggestion,
  yearLabel,
  noDataLabel,
}: CounterfactualCardProps) {
  const sorted = useMemo(
    () => [...categories].sort((a, b) => b.total - a.total).slice(0, 8),
    [categories],
  )
  const [picked, setPicked] = useState<Set<string>>(new Set())

  const togglePick = (key: string) => {
    setPicked((prev) => {
      const next = new Set(prev)
      if (next.has(key)) next.delete(key)
      else next.add(key)
      return next
    })
  }

  const scale = windowDays > 0 ? 365 / windowDays : 0
  const windowSavings = sorted
    .filter((c) => picked.has(key(c)))
    .reduce((sum, c) => sum + c.total, 0)
  const annualSavings = windowSavings * scale

  return (
    <Card>
      <CardHeader>
        <CardTitle>{title}</CardTitle>
        <p className="text-sm text-muted-foreground">{subtitle}</p>
      </CardHeader>
      <CardContent>
        {sorted.length === 0 ? (
          <p className="py-6 text-center text-sm text-muted-foreground">{noDataLabel}</p>
        ) : (
          <>
            <div className="mb-3 rounded-md bg-emerald-500/10 px-3 py-2 text-sm dark:bg-emerald-500/5">
              <span className="text-muted-foreground">{suggestion}: </span>
              <span className="font-semibold tabular-nums text-emerald-700 dark:text-emerald-300">
                {formatCurrency(annualSavings)}
              </span>
              <span className="ml-1 text-[11px] text-muted-foreground">/ {yearLabel}</span>
            </div>
            <ul className="space-y-1">
              {sorted.map((c) => {
                const k = key(c)
                const on = picked.has(k)
                return (
                  <li key={k}>
                    <label className="flex cursor-pointer items-center gap-3 rounded-md px-2 py-1.5 hover:bg-muted/40">
                      <input
                        type="checkbox"
                        checked={on}
                        onChange={() => togglePick(k)}
                        className="rounded"
                      />
                      <span className="min-w-0 flex-1 truncate text-sm">
                        {c.emoji ? `${c.emoji} ` : ''}
                        {c.categoryName}
                      </span>
                      <span className="text-xs text-muted-foreground">{c.groupName}</span>
                      <span className="w-24 text-right text-sm font-medium tabular-nums">
                        {formatCurrency(c.total * scale)}
                        <span className="ml-1 text-[10px] text-muted-foreground">/yr</span>
                      </span>
                    </label>
                  </li>
                )
              })}
            </ul>
          </>
        )}
      </CardContent>
    </Card>
  )
}

function key(c: CategoryShare): string {
  return `${c.groupName}::${c.categoryName}`
}
