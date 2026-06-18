'use client'

import { CalendarClock } from 'lucide-react'
import type { LeftToSpend } from '../../types'
import { Card, CardContent, CardHeader, CardTitle } from '../ui/card'
import { computeMonthForecast } from '../../lib/reflect/insights'
import { formatCurrency, formatCurrencySigned } from '../../lib/format/currency'
import { useT } from '../../i18n/context'

interface MonthForecastCardProps {
  leftToSpend: LeftToSpend
}

/**
 * "Where will the month land?" — projects total spend at the current daily
 * pace and, when a salary is detected, the resulting margin. A thin bar shows
 * how far through the month we are so the projection is read in context.
 */
export function MonthForecastCard({ leftToSpend }: MonthForecastCardProps) {
  const t = useT()
  const f = computeMonthForecast(leftToSpend)
  const totalDays = Math.max(1, f.daysElapsed + f.daysRemaining)
  const elapsedPct = Math.min(100, Math.round((f.daysElapsed / totalDays) * 100))

  const hasMargin = f.projectedMargin !== null
  const headlineValue = hasMargin
    ? formatCurrencySigned(f.projectedMargin as number)
    : formatCurrency(f.projectedSpend)
  const headlineTone = !hasMargin
    ? 'text-foreground'
    : f.onTrack
      ? 'text-emerald-600 dark:text-emerald-400'
      : 'text-destructive'

  return (
    <Card className="flex h-full flex-col">
      <CardHeader className="flex flex-row items-center justify-between gap-2 space-y-0 pb-2">
        <div className="min-w-0">
          <CardTitle className="text-sm font-medium">
            {t('reflect.insights.forecastTitle', 'Month forecast')}
          </CardTitle>
          <p className="mt-0.5 text-[11px] text-muted-foreground">
            {t('reflect.insights.forecastSubtitle', 'If your current pace holds')}
          </p>
        </div>
        <CalendarClock className="h-4 w-4 shrink-0 text-muted-foreground" />
      </CardHeader>
      <CardContent className="flex min-h-0 flex-1 flex-col justify-between gap-3 pb-3">
        <div>
          <p className={`text-2xl font-bold tabular-nums ${headlineTone}`}>{headlineValue}</p>
          <p className="mt-0.5 text-[11px] text-muted-foreground">
            {hasMargin
              ? t('reflect.insights.forecastMargin', 'projected margin')
              : t('reflect.insights.forecastSpend', 'projected spend')}
          </p>
        </div>

        <div className="space-y-2 text-[11px] text-muted-foreground">
          <div className="flex items-center justify-between tabular-nums">
            <span>{t('reflect.insights.spentSoFar', 'Spent so far')}</span>
            <span className="text-foreground">{formatCurrency(f.monthSpent)}</span>
          </div>
          <div className="flex items-center justify-between tabular-nums">
            <span>{t('reflect.insights.projectedTotal', 'Projected total spend')}</span>
            <span className="text-foreground">{formatCurrency(f.projectedSpend)}</span>
          </div>
          <div>
            <div className="mb-1 flex items-center justify-between">
              <span>
                {t('reflect.insights.dayOfMonth', { n: f.daysElapsed, total: totalDays }, 'Day {n} of {total}')}
              </span>
              <span className="tabular-nums">{elapsedPct}%</span>
            </div>
            <div className="h-1.5 overflow-hidden rounded-full bg-muted">
              <div
                className="h-full rounded-full bg-foreground/40"
                style={{ width: `${elapsedPct}%` }}
              />
            </div>
          </div>
          {f.fixedSpent > 0 && (
            <p className="text-[10px] leading-snug text-muted-foreground/80">
              {t(
                'reflect.insights.forecastFixedNote',
                { amount: formatCurrency(f.fixedSpent) },
                'Fixed bills ({amount}) kept as-is — only variable spend is projected forward.',
              )}
            </p>
          )}
        </div>
      </CardContent>
    </Card>
  )
}
