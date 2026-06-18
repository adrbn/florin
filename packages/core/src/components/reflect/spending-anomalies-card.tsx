'use client'

import Link from 'next/link'
import { TriangleAlert } from 'lucide-react'
import type { DailyCategorySpend } from '../../types'
import { Card, CardContent, CardHeader, CardTitle } from '../ui/card'
import { computeSpendingAnomalies } from '../../lib/reflect/insights'
import { formatCurrency } from '../../lib/format/currency'
import { useLocale, useT } from '../../i18n/context'

interface SpendingAnomaliesCardProps {
  rows: ReadonlyArray<DailyCategorySpend>
}

/**
 * Days that cost far more than a typical spending day. Each one links into the
 * transactions list filtered to that day so the user can see what happened.
 */
export function SpendingAnomaliesCard({ rows }: SpendingAnomaliesCardProps) {
  const t = useT()
  const locale = useLocale()
  const { typicalDay, anomalies } = computeSpendingAnomalies(rows)
  const dateFmt = new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'short', year: '2-digit' })

  return (
    <Card className="flex h-full flex-col">
      <CardHeader className="pb-2">
        <CardTitle className="text-sm font-medium">
          {t('reflect.insights.anomaliesTitle', 'Unusual days')}
        </CardTitle>
        <p className="mt-0.5 text-[11px] text-muted-foreground">
          {typicalDay > 0
            ? t(
                'reflect.insights.anomaliesSubtitle',
                { amount: formatCurrency(typicalDay) },
                'vs your typical {amount} spending day',
              )
            : t('reflect.insights.anomaliesSubtitleGeneric', 'Days well above your normal spend')}
          {' · '}
          {t('reflect.insights.anomaliesFixedNote', 'fixed bills excluded')}
        </p>
      </CardHeader>
      <CardContent className="min-h-0 flex-1 pb-3">
        {anomalies.length === 0 ? (
          <p className="py-6 text-center text-xs text-muted-foreground">
            {t('reflect.insights.anomaliesEmpty', 'Nothing unusual — your days are steady.')}
          </p>
        ) : (
          <ul className="space-y-2">
            {anomalies.map((a) => (
              <li key={a.date}>
                <Link
                  href={{
                    pathname: '/transactions',
                    query: { from: a.date, to: a.date, direction: 'expense' },
                  }}
                  className="flex items-center gap-2 rounded-md px-1 py-1 text-sm transition-colors hover:bg-muted/40"
                >
                  <TriangleAlert className="h-3.5 w-3.5 shrink-0 text-amber-500" />
                  <div className="min-w-0 flex-1">
                    <p className="truncate font-medium">{dateFmt.format(new Date(a.date))}</p>
                    {a.topCategoryName ? (
                      <p className="truncate text-[11px] text-muted-foreground">
                        {t('reflect.insights.anomalyMostly', 'mostly')} {a.topCategoryName}
                      </p>
                    ) : null}
                  </div>
                  <div className="shrink-0 text-right">
                    <p className="font-medium tabular-nums text-destructive">
                      {formatCurrency(a.amount)}
                    </p>
                    <p className="text-[11px] text-muted-foreground tabular-nums">
                      ×{a.multipleOfTypical.toFixed(1)}
                    </p>
                  </div>
                </Link>
              </li>
            ))}
          </ul>
        )}
      </CardContent>
    </Card>
  )
}
