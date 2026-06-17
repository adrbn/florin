'use client'

import { ArrowDownRight, ArrowUpRight } from 'lucide-react'
import type { CategorySpendingSeries } from '../../types'
import { Card, CardContent, CardHeader, CardTitle } from '../ui/card'
import { computeCategoryMovers } from '../../lib/reflect/insights'
import { formatCurrency, formatCurrencySigned } from '../../lib/format/currency'
import { useLocale, useT } from '../../i18n/context'

interface CategoryMoversCardProps {
  series: CategorySpendingSeries
}

function formatMonth(month: string | null, locale: string): string {
  if (!month) return ''
  const [y, m] = month.split('-')
  if (!y || !m) return month
  return new Date(Number(y), Number(m) - 1, 1).toLocaleDateString(locale, {
    month: 'short',
    year: '2-digit',
  })
}

/**
 * Biggest month-over-month category changes — "what changed" at a glance.
 * Spending going UP is the destructive direction (red), going down is green.
 */
export function CategoryMoversCard({ series }: CategoryMoversCardProps) {
  const t = useT()
  const locale = useLocale()
  const { currentMonth, previousMonth, movers } = computeCategoryMovers(series)

  return (
    <Card className="flex h-full flex-col">
      <CardHeader className="pb-2">
        <CardTitle className="text-sm font-medium">
          {t('reflect.insights.moversTitle', 'Biggest movers')}
        </CardTitle>
        <p className="mt-0.5 text-[11px] text-muted-foreground">
          {currentMonth && previousMonth
            ? `${formatMonth(previousMonth, locale)} → ${formatMonth(currentMonth, locale)}`
            : t('reflect.insights.moversSubtitle', 'Month-over-month change by category')}
        </p>
      </CardHeader>
      <CardContent className="min-h-0 flex-1 pb-3">
        {movers.length === 0 ? (
          <p className="py-6 text-center text-xs text-muted-foreground">
            {t('reflect.insights.moversEmpty', 'Not enough history to compare months yet.')}
          </p>
        ) : (
          <ul className="space-y-2">
            {movers.map((m) => {
              const up = m.delta > 0
              const Icon = up ? ArrowUpRight : ArrowDownRight
              const tone = up ? 'text-destructive' : 'text-emerald-600 dark:text-emerald-400'
              return (
                <li key={m.categoryId} className="flex items-center gap-2 text-sm">
                  <div className="min-w-0 flex-1">
                    <p className="truncate font-medium">
                      {m.emoji ? `${m.emoji} ` : ''}
                      {m.categoryName}
                    </p>
                    <p className="truncate text-[11px] text-muted-foreground tabular-nums">
                      {formatCurrency(m.previous)} → {formatCurrency(m.current)}
                    </p>
                  </div>
                  <div className={`flex shrink-0 items-center gap-1 tabular-nums ${tone}`}>
                    <Icon className="h-3.5 w-3.5" />
                    <span className="font-medium">{formatCurrencySigned(m.delta)}</span>
                    {m.pct !== null ? (
                      <span className="text-[11px] opacity-80">
                        {m.pct >= 0 ? '+' : ''}
                        {Math.round(m.pct)}%
                      </span>
                    ) : (
                      <span className="text-[11px] opacity-80">
                        {t('reflect.insights.moverNew', 'new')}
                      </span>
                    )}
                  </div>
                </li>
              )
            })}
          </ul>
        )}
      </CardContent>
    </Card>
  )
}
