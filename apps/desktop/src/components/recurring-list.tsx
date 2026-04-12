'use client'

import { formatCurrency } from '@florin/core/lib/format'
import type { RecurringPattern } from '@/server/actions/recurring'

interface RecurringListProps {
  patterns: RecurringPattern[]
}

function frequencyLabel(days: number): string {
  if (days <= 8) return 'Weekly'
  if (days <= 16) return 'Biweekly'
  if (days <= 35) return 'Monthly'
  if (days <= 65) return 'Bimonthly'
  return 'Quarterly'
}

export function RecurringList({ patterns }: RecurringListProps) {
  if (patterns.length === 0) {
    return (
      <p className="py-8 text-center text-sm text-muted-foreground">
        No recurring transactions detected yet. Once you have 3+ payments to the same payee, patterns will appear here.
      </p>
    )
  }

  const totalMonthlyBurn = patterns.reduce((acc, p) => {
    const monthlyAmount = (Math.abs(p.avgAmount) * 30) / p.avgDaysBetween
    return acc + monthlyAmount
  }, 0)

  return (
    <div className="space-y-4">
      <div className="rounded-lg border border-border bg-muted/30 px-4 py-3">
        <p className="text-xs uppercase tracking-wide text-muted-foreground">Estimated monthly recurring</p>
        <p className="text-2xl font-bold tabular-nums">{formatCurrency(totalMonthlyBurn)}</p>
      </div>

      <div className="divide-y divide-border rounded-lg border border-border">
        {patterns.map((p) => {
          const isPast = new Date(p.predictedNextDate) < new Date()
          return (
            <div key={p.normalizedPayee} className="flex items-center gap-3 px-4 py-3">
              <div className="flex h-8 w-8 items-center justify-center rounded-full bg-muted text-sm">
                {p.categoryEmoji ?? '💳'}
              </div>
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-medium">{p.payee}</p>
                <p className="text-xs text-muted-foreground">
                  {frequencyLabel(p.avgDaysBetween)} · {p.occurrences}x · {p.categoryName ?? 'Uncategorized'}
                </p>
              </div>
              <div className="text-right">
                <p className="text-sm font-semibold tabular-nums text-destructive">
                  {formatCurrency(p.avgAmount)}
                </p>
                <p className={`text-[10px] ${isPast ? 'text-amber-500' : 'text-muted-foreground'}`}>
                  {isPast ? 'Expected' : 'Next'}: {p.predictedNextDate}
                </p>
              </div>
            </div>
          )
        })}
      </div>
    </div>
  )
}
