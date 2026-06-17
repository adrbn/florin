'use client'

import { Repeat } from 'lucide-react'
import type { SubscriptionMatch } from '../../types'
import { Card, CardContent, CardHeader, CardTitle } from '../ui/card'
import { computeRecurringSplit } from '../../lib/reflect/insights'
import { formatCurrency } from '../../lib/format/currency'
import { useT } from '../../i18n/context'

interface RecurringSplitCardProps {
  subscriptions: ReadonlyArray<SubscriptionMatch>
  /** Average total monthly spend — the denominator for the split. */
  avgMonthlySpend: number
}

/**
 * How much of an average month is already spoken for (recurring subscriptions
 * & bills) vs free to choose. A single stacked bar makes the ratio obvious.
 */
export function RecurringSplitCard({ subscriptions, avgMonthlySpend }: RecurringSplitCardProps) {
  const t = useT()
  const split = computeRecurringSplit(subscriptions, avgMonthlySpend)
  const committedPct = Math.round(split.committedPct)
  const discretionaryPct = Math.max(0, 100 - committedPct)

  return (
    <Card className="flex h-full flex-col">
      <CardHeader className="flex flex-row items-center justify-between gap-2 space-y-0 pb-2">
        <div className="min-w-0">
          <CardTitle className="text-sm font-medium">
            {t('reflect.insights.recurringTitle', 'Committed vs free')}
          </CardTitle>
          <p className="mt-0.5 text-[11px] text-muted-foreground">
            {t(
              'reflect.insights.recurringSubtitle',
              { n: split.subscriptionCount },
              '{n} recurring charges of a typical month',
            )}
          </p>
        </div>
        <Repeat className="h-4 w-4 shrink-0 text-muted-foreground" />
      </CardHeader>
      <CardContent className="flex min-h-0 flex-1 flex-col justify-between gap-3 pb-3">
        <div>
          <p className="text-2xl font-bold tabular-nums">{committedPct}%</p>
          <p className="mt-0.5 text-[11px] text-muted-foreground">
            {t('reflect.insights.recurringCommittedLabel', 'of your spending is committed')}
          </p>
        </div>

        {split.totalMonthly > 0 ? (
          <div className="space-y-2">
            <div className="flex h-2.5 overflow-hidden rounded-full bg-muted">
              <div
                className="h-full bg-amber-500/80"
                style={{ width: `${committedPct}%` }}
                aria-hidden
              />
              <div
                className="h-full bg-emerald-500/70"
                style={{ width: `${discretionaryPct}%` }}
                aria-hidden
              />
            </div>
            <div className="flex items-center justify-between text-[11px] tabular-nums">
              <span className="flex items-center gap-1.5">
                <span className="h-2 w-2 rounded-full bg-amber-500/80" aria-hidden />
                <span className="text-muted-foreground">
                  {t('reflect.insights.recurringCommitted', 'Committed')}
                </span>
                <span className="font-medium text-foreground">
                  {formatCurrency(split.committedMonthly)}
                </span>
              </span>
              <span className="flex items-center gap-1.5">
                <span className="h-2 w-2 rounded-full bg-emerald-500/70" aria-hidden />
                <span className="text-muted-foreground">
                  {t('reflect.insights.recurringFree', 'Free')}
                </span>
                <span className="font-medium text-foreground">
                  {formatCurrency(split.discretionaryMonthly)}
                </span>
              </span>
            </div>
          </div>
        ) : (
          <p className="text-xs text-muted-foreground">
            {t('reflect.insights.recurringEmpty', 'Not enough spending history yet.')}
          </p>
        )}
      </CardContent>
    </Card>
  )
}
