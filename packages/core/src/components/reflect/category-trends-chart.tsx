'use client'

import { useMemo, useState } from 'react'
import Link from 'next/link'
import type { CategorySpendingSeries } from '../../types'
import { Card, CardContent, CardHeader, CardTitle } from '../ui/card'
import { CATEGORICAL_PALETTE } from '../../lib/chart/palette'
import { formatCurrency } from '../../lib/format/currency'
import { useT } from '../../i18n/context'

type WindowMonths = 6 | 12 | 24

interface Props {
  data: CategorySpendingSeries
  title?: string
  subtitle?: string
  emptyMessage?: string
  /**
   * When true each sparkline tile becomes a link that drills into the
   * transactions list pre-filtered to that category.
   * (Can't accept a function prop — server→client serialization would fail.)
   */
  linkToTransactions?: boolean
}

/**
 * Split a per-month series in half and compute the %-change between the
 * recent half's mean and the older half's mean. Returns null when the
 * series is too short or the older half was zero — a pure appearance isn't
 * a meaningful "+∞%". Clamps to [-999, 999] so the chip doesn't explode
 * when a baseline is very small.
 */
function recentTrendPct(monthly: readonly number[]): number | null {
  if (monthly.length < 4) return null
  const mid = Math.floor(monthly.length / 2)
  const older = monthly.slice(0, mid)
  const recent = monthly.slice(mid)
  const olderAvg = older.reduce((s, v) => s + v, 0) / Math.max(1, older.length)
  const recentAvg = recent.reduce((s, v) => s + v, 0) / Math.max(1, recent.length)
  if (olderAvg <= 0.01) return null
  const pct = ((recentAvg - olderAvg) / olderAvg) * 100
  return Math.max(-999, Math.min(999, pct))
}

/**
 * Slice the series into the last `windowMonths` and re-rank categories by
 * spend within that window. Categories with zero spend in the window drop
 * out entirely so the list doesn't show stale names from a year ago.
 */
function sliceWindow(data: CategorySpendingSeries, windowMonths: number): CategorySpendingSeries {
  const start = Math.max(0, data.months.length - windowMonths)
  const months = data.months.slice(start)
  const categories = data.categories
    .map((c) => {
      const monthly = c.monthly.slice(start)
      const total = monthly.reduce((s, v) => s + v, 0)
      return { ...c, monthly, total }
    })
    .filter((c) => c.total > 0)
    .sort((a, b) => b.total - a.total)
  return { months, categories }
}

/**
 * Tiny inline sparkline — raw SVG because we render one per category and
 * Recharts per-card would torch CPU. No axes, no labels, just the shape of
 * the series. Baseline-padded with max so the line doesn't hit the edges
 * and feels a bit aerated in a small tile.
 */
function Sparkline({ values, color }: { values: readonly number[]; color: string }) {
  if (values.length < 2) {
    return <div className="h-10 w-full rounded bg-muted/30" />
  }
  const max = Math.max(...values, 1)
  const w = 100
  const h = 32
  const step = values.length > 1 ? w / (values.length - 1) : w
  const points = values
    .map((v, i) => `${(i * step).toFixed(2)},${(h - (v / max) * (h - 2) - 1).toFixed(2)}`)
    .join(' ')
  // Closed area under the line — filled with a faded version of the stroke
  // colour for a subtle "volume" feel without the formal axis.
  const areaPoints = `0,${h} ${points} ${w},${h}`
  const gradientId = `spark-grad-${Math.abs(
    values.reduce((s, v, i) => s + v * (i + 1), 0),
  )
    .toString(36)
    .slice(0, 8)}`
  return (
    <svg viewBox={`0 0 ${w} ${h}`} className="h-10 w-full" preserveAspectRatio="none">
      <defs>
        <linearGradient id={gradientId} x1="0" x2="0" y1="0" y2="1">
          <stop offset="0%" stopColor={color} stopOpacity="0.35" />
          <stop offset="100%" stopColor={color} stopOpacity="0" />
        </linearGradient>
      </defs>
      <polygon points={areaPoints} fill={`url(#${gradientId})`} />
      <polyline points={points} fill="none" stroke={color} strokeWidth="1.5" />
    </svg>
  )
}

/**
 * Small-multiples category trend view. One compact tile per category, each
 * with a tiny sparkline, total spend in the selected window, and a trend
 * chip showing how the recent half compares to the older half. Tiles are
 * sorted by total spend so the expensive categories surface immediately —
 * no filter-chip dance to find them.
 *
 * Replaces the old overloaded single-chart view where 20 overlapping lines
 * made nothing readable. Users that want to compare a handful of lines on
 * the same axis can open any one tile to drill into the filtered
 * transactions list.
 */
export function CategoryTrendsChart({
  data,
  title,
  subtitle,
  emptyMessage,
  linkToTransactions = true,
}: Props) {
  const t = useT()
  const effectiveTitle = title ?? t('reflect.categoryTrendsTitle', 'Spending by category')
  const effectiveSubtitle =
    subtitle ??
    t(
      'reflect.categoryTrendsSubtitle',
      'One sparkline per category — sorted by total spend in the window.',
    )
  const effectiveEmpty = emptyMessage ?? t('reflect.noSpendingData', 'Not enough spending history yet.')

  const availableMonths = data.months.length
  const [windowMonths, setWindowMonths] = useState<WindowMonths>(12)
  const windowed = useMemo(
    () => sliceWindow(data, Math.min(windowMonths, availableMonths)),
    [data, windowMonths, availableMonths],
  )

  const windowOptions: WindowMonths[] = [6, 12, 24]
  const monthLabel = t('reflect.trendWindowMonths', 'm')

  return (
    <Card className="flex h-full flex-col">
      <CardHeader className="gap-1 pb-2">
        <div className="flex items-center justify-between gap-3">
          <div className="min-w-0">
            <CardTitle className="text-xs uppercase tracking-wide text-muted-foreground">
              {effectiveTitle}
            </CardTitle>
            {effectiveSubtitle ? (
              <p className="mt-0.5 text-xs text-muted-foreground">{effectiveSubtitle}</p>
            ) : null}
          </div>
          <div className="inline-flex overflow-hidden rounded-md border border-border text-[10px]">
            {windowOptions.map((opt) => {
              const disabled = opt > availableMonths && opt !== 6
              const active = windowMonths === opt
              return (
                <button
                  key={opt}
                  type="button"
                  onClick={() => setWindowMonths(opt)}
                  disabled={disabled}
                  className={`px-2 py-0.5 font-medium transition ${
                    active
                      ? 'bg-foreground text-background'
                      : 'text-muted-foreground hover:bg-muted/60'
                  } ${disabled ? 'opacity-40' : ''}`}
                >
                  {opt}
                  {monthLabel}
                </button>
              )
            })}
          </div>
        </div>
      </CardHeader>
      <CardContent className="min-h-0 flex-1 pb-3">
        {windowed.categories.length === 0 ? (
          <p className="py-6 text-center text-xs text-muted-foreground">{effectiveEmpty}</p>
        ) : (
          <ul className="grid grid-cols-1 gap-2 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
            {windowed.categories.map((c, i) => {
              const color =
                CATEGORICAL_PALETTE[i % CATEGORICAL_PALETTE.length] ?? CATEGORICAL_PALETTE[0]!
              const trend = recentTrendPct(c.monthly)
              const trendLabel =
                trend === null
                  ? null
                  : `${trend >= 0 ? '▲' : '▼'} ${Math.abs(trend).toFixed(0)}%`
              const trendClass =
                trend === null
                  ? 'text-muted-foreground'
                  : trend >= 10
                    ? 'text-destructive'
                    : trend <= -10
                      ? 'text-emerald-600 dark:text-emerald-400'
                      : 'text-muted-foreground'
              const avg = c.monthly.length > 0 ? c.total / c.monthly.length : 0
              const href = linkToTransactions
                ? `/transactions?category=${encodeURIComponent(c.categoryId)}&direction=expense`
                : null

              const body = (
                <div className="flex h-full flex-col gap-1.5 rounded-lg border border-border bg-muted/10 p-2.5 transition-colors hover:border-foreground/30 hover:bg-muted/30">
                  <div className="flex items-start justify-between gap-2">
                    <span className="flex min-w-0 items-center gap-1.5 text-[12px] font-medium">
                      <span
                        aria-hidden
                        className="h-2 w-2 flex-shrink-0 rounded-full"
                        style={{ backgroundColor: color }}
                      />
                      <span className="truncate">
                        {c.emoji ? `${c.emoji} ` : ''}
                        {c.categoryName}
                      </span>
                    </span>
                    {trendLabel ? (
                      <span className={`flex-shrink-0 text-[10px] tabular-nums ${trendClass}`}>
                        {trendLabel}
                      </span>
                    ) : null}
                  </div>
                  <Sparkline values={c.monthly} color={color} />
                  <div className="flex items-baseline justify-between gap-2 text-[10px] text-muted-foreground">
                    <span className="tabular-nums text-foreground">{formatCurrency(c.total)}</span>
                    <span className="tabular-nums">
                      {formatCurrency(avg)}{' '}
                      {t('reflect.trendPerMonth', '/mo')}
                    </span>
                  </div>
                </div>
              )

              return (
                <li key={c.categoryId}>
                  {href ? (
                    <Link href={href as never} className="block h-full">
                      {body}
                    </Link>
                  ) : (
                    body
                  )}
                </li>
              )
            })}
          </ul>
        )}
      </CardContent>
    </Card>
  )
}
