import { Repeat } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '../ui/card'
import { formatCurrency } from '../../lib/format/currency'
import type { SubscriptionMatch } from '../../types/index'

interface SubscriptionsListProps {
  rows: ReadonlyArray<SubscriptionMatch>
  title: string
  subtitle: string
  empty: string
  annualLabel: string
  cadenceMonthly: string
  cadenceWeekly: string
  cadenceOther: (days: number) => string
}

/**
 * Subscriptions radar — the backing detector returns sorted-by-annual-cost,
 * so we simply render the list with a running total at the top to make the
 * "if you dropped all of these…" framing obvious.
 */
export function SubscriptionsList({
  rows,
  title,
  subtitle,
  empty,
  annualLabel,
  cadenceMonthly,
  cadenceWeekly,
  cadenceOther,
}: SubscriptionsListProps) {
  const totalAnnual = rows.reduce((sum, r) => sum + r.annualCost, 0)

  return (
    <Card>
      <CardHeader>
        <CardTitle>{title}</CardTitle>
        <p className="text-sm text-muted-foreground">{subtitle}</p>
      </CardHeader>
      <CardContent>
        {rows.length === 0 ? (
          <p className="py-6 text-center text-sm text-muted-foreground">{empty}</p>
        ) : (
          <div className="space-y-3">
            <div className="rounded-md bg-muted/40 px-3 py-2 text-sm">
              <span className="text-muted-foreground">{annualLabel}: </span>
              <span className="font-semibold tabular-nums">{formatCurrency(totalAnnual)}</span>
            </div>
            <ul className="divide-y divide-border">
              {rows.map((r) => (
                <li key={`${r.payee}-${r.amount}`} className="flex items-center gap-3 py-2">
                  <Repeat className="h-4 w-4 text-muted-foreground shrink-0" />
                  <div className="min-w-0 flex-1">
                    <div className="truncate font-medium">{r.payee}</div>
                    <div className="text-[11px] text-muted-foreground">
                      {cadenceLabel(r.cadenceDays, cadenceMonthly, cadenceWeekly, cadenceOther)}
                      {r.categoryName ? ` · ${r.categoryName}` : ''}
                    </div>
                  </div>
                  <div className="text-right">
                    <div className="tabular-nums font-medium">{formatCurrency(Math.abs(r.amount))}</div>
                    <div className="text-[11px] text-muted-foreground tabular-nums">
                      {formatCurrency(r.annualCost)} / yr
                    </div>
                  </div>
                </li>
              ))}
            </ul>
          </div>
        )}
      </CardContent>
    </Card>
  )
}

function cadenceLabel(
  days: number,
  monthly: string,
  weekly: string,
  other: (days: number) => string,
): string {
  if (Math.abs(days - 30) <= 7) return monthly
  if (Math.abs(days - 7) <= 2) return weekly
  return other(days)
}
