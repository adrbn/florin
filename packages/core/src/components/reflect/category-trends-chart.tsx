'use client'

import { useMemo, useState } from 'react'
import Link from 'next/link'
import {
  Area,
  AreaChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'
import { ArrowRight } from 'lucide-react'
import type { CategorySpendingSeries } from '../../types'
import { Card, CardContent, CardHeader, CardTitle } from '../ui/card'
import { Dialog, DialogContent, DialogTitle } from '../ui/dialog'
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

function formatMonth(m: string): string {
  const [year, month] = m.split('-')
  if (!year || !month) return m
  const d = new Date(Number(year), Number(month) - 1, 1)
  return d.toLocaleDateString(undefined, { month: 'short', year: '2-digit' })
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
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const windowed = useMemo(
    () => sliceWindow(data, Math.min(windowMonths, availableMonths)),
    [data, windowMonths, availableMonths],
  )

  const windowOptions: WindowMonths[] = [6, 12, 24]
  const monthLabel = t('reflect.trendWindowMonths', 'm')

  const selectedIndex = selectedId
    ? windowed.categories.findIndex((c) => c.categoryId === selectedId)
    : -1
  const selected = selectedIndex >= 0 ? windowed.categories[selectedIndex] : null
  const selectedColor =
    selected !== null
      ? (CATEGORICAL_PALETTE[selectedIndex % CATEGORICAL_PALETTE.length] ??
        CATEGORICAL_PALETTE[0]!)
      : CATEGORICAL_PALETTE[0]!

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

              return (
                <li key={c.categoryId}>
                  <button
                    type="button"
                    onClick={() => setSelectedId(c.categoryId)}
                    className="group flex h-full w-full flex-col gap-1.5 rounded-lg border border-border bg-muted/10 p-2.5 text-left transition-colors hover:border-foreground/30 hover:bg-muted/30 focus-visible:border-foreground/50 focus-visible:outline-none"
                    aria-label={t(
                      'reflect.viewCategoryTrend',
                      { name: c.categoryName },
                      'View {name} trend',
                    )}
                  >
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
                  </button>
                </li>
              )
            })}
          </ul>
        )}
      </CardContent>

      <Dialog open={selected !== null} onOpenChange={(o) => { if (!o) setSelectedId(null) }}>
        {selected ? (
          <DialogContent
            className="sm:max-w-2xl"
            aria-describedby={undefined}
          >
            <DialogTitle className="flex items-center gap-2 text-base">
              <span
                aria-hidden
                className="h-2.5 w-2.5 rounded-full"
                style={{ backgroundColor: selectedColor }}
              />
              <span>
                {selected.emoji ? `${selected.emoji} ` : ''}
                {selected.categoryName}
              </span>
            </DialogTitle>

            <CategoryTrendDetail
              months={windowed.months}
              monthly={selected.monthly}
              total={selected.total}
              color={selectedColor}
              totalLabel={t('reflect.totalLabel', 'Total')}
              avgLabel={t('reflect.trendPerMonth', '/mo')}
              trendLabel={t('reflect.trendLabel', 'Trend')}
              maxLabel={t('reflect.maxMonthLabel', 'Peak')}
            />

            {linkToTransactions ? (
              <div className="-mx-4 -mb-4 flex items-center justify-end gap-2 rounded-b-xl border-t bg-muted/50 px-4 py-3">
                <Link
                  href={
                    `/transactions?category=${encodeURIComponent(selected.categoryId)}&direction=expense` as never
                  }
                  className="inline-flex items-center gap-1.5 text-sm font-medium text-foreground hover:underline"
                  onClick={() => setSelectedId(null)}
                >
                  {t('reflect.seeTransactions', 'See transactions')}
                  <ArrowRight className="h-3.5 w-3.5" />
                </Link>
              </div>
            ) : null}
          </DialogContent>
        ) : null}
      </Dialog>
    </Card>
  )
}

interface DetailProps {
  months: readonly string[]
  monthly: readonly number[]
  total: number
  color: string
  totalLabel: string
  avgLabel: string
  trendLabel: string
  maxLabel: string
}

function CategoryTrendDetail({
  months,
  monthly,
  total,
  color,
  totalLabel,
  avgLabel,
  trendLabel,
  maxLabel,
}: DetailProps) {
  const points = months.map((m, i) => ({ month: m, value: monthly[i] ?? 0 }))
  const avg = monthly.length > 0 ? total / monthly.length : 0
  const maxValue = monthly.length > 0 ? Math.max(...monthly) : 0
  const maxIndex = monthly.indexOf(maxValue)
  const maxMonth = maxIndex >= 0 ? months[maxIndex] : null
  const trend = recentTrendPct(monthly)
  const gradientId = `catdetail-grad-${Math.abs(
    monthly.reduce((s, v, i) => s + v * (i + 1), 0),
  )
    .toString(36)
    .slice(0, 8)}`

  return (
    <div className="flex flex-col gap-3">
      <div className="grid grid-cols-3 gap-3 text-xs">
        <Stat label={totalLabel} value={formatCurrency(total)} />
        <Stat label={avgLabel} value={formatCurrency(avg)} />
        <Stat
          label={trendLabel}
          value={
            trend === null
              ? '—'
              : `${trend >= 0 ? '▲' : '▼'} ${Math.abs(trend).toFixed(0)}%`
          }
          tone={
            trend === null
              ? 'neutral'
              : trend >= 10
                ? 'down'
                : trend <= -10
                  ? 'up'
                  : 'neutral'
          }
        />
      </div>

      <div className="h-56 w-full">
        <ResponsiveContainer width="100%" height="100%">
          <AreaChart data={points} margin={{ top: 8, right: 8, bottom: 0, left: 0 }}>
            <defs>
              <linearGradient id={gradientId} x1="0" x2="0" y1="0" y2="1">
                <stop offset="0%" stopColor={color} stopOpacity={0.35} />
                <stop offset="100%" stopColor={color} stopOpacity={0} />
              </linearGradient>
            </defs>
            <CartesianGrid
              stroke="currentColor"
              strokeOpacity={0.08}
              vertical={false}
            />
            <XAxis
              dataKey="month"
              tick={{ fontSize: 10, fill: 'currentColor', opacity: 0.6 }}
              tickLine={false}
              axisLine={false}
              tickFormatter={formatMonth}
              minTickGap={16}
            />
            <YAxis
              tick={{ fontSize: 10, fill: 'currentColor', opacity: 0.6 }}
              tickLine={false}
              axisLine={false}
              width={48}
              tickFormatter={(v: number) =>
                v >= 1000 ? `${Math.round(v / 1000)}k` : Math.round(v).toString()
              }
            />
            <Tooltip
              cursor={{ stroke: color, strokeOpacity: 0.3, strokeWidth: 1 }}
              contentStyle={{
                background: 'var(--popover)',
                border: '1px solid var(--border)',
                borderRadius: 6,
                fontSize: 12,
                padding: '6px 10px',
              }}
              labelFormatter={(m) => formatMonth(String(m))}
              formatter={(v) => [formatCurrency(Number(v)), ''] as [string, string]}
              separator=""
            />
            <Area
              type="monotone"
              dataKey="value"
              stroke={color}
              strokeWidth={2}
              fill={`url(#${gradientId})`}
              dot={false}
              activeDot={{ r: 4, stroke: color, strokeWidth: 2, fill: 'var(--background)' }}
            />
          </AreaChart>
        </ResponsiveContainer>
      </div>

      {maxMonth ? (
        <p className="text-[11px] text-muted-foreground">
          {maxLabel}: {formatCurrency(maxValue)} · {formatMonth(maxMonth)}
        </p>
      ) : null}
    </div>
  )
}

function Stat({
  label,
  value,
  tone = 'neutral',
}: {
  label: string
  value: string
  tone?: 'up' | 'down' | 'neutral'
}) {
  const toneClass =
    tone === 'up'
      ? 'text-emerald-600 dark:text-emerald-400'
      : tone === 'down'
        ? 'text-destructive'
        : 'text-foreground'
  return (
    <div className="rounded-lg border border-border bg-muted/20 px-3 py-2">
      <p className="text-[10px] uppercase tracking-wide text-muted-foreground">{label}</p>
      <p className={`mt-0.5 text-sm font-semibold tabular-nums ${toneClass}`}>{value}</p>
    </div>
  )
}
