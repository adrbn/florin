'use client'

import { useMemo, useState } from 'react'
import {
  Area,
  CartesianGrid,
  ComposedChart,
  Line,
  ReferenceLine,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'
import { Button } from '../ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '../ui/card'
import { NoSSR } from '../ui/no-ssr'
import { useLocale, useT } from '../../i18n/context'
import {
  formatCurrency,
  formatCurrencyCompact,
  formatCurrencySigned,
} from '../../lib/format/currency'
import { usePlayOnce } from '../../lib/use-play-once'

/** Average days per month — converts the per-day slope to a monthly figure. */
const DAYS_PER_MONTH = 30.4368

export interface PatrimonyPoint {
  date: string
  balance: number
}

const FORECAST_MONTHS = 12
const DAY_MS = 24 * 60 * 60 * 1000

/**
 * Lookback windows the user can pick for the trend regression. The slope is
 * fit only on points within the window, so "30 days" shows what would happen
 * if the last month's habits held, while "All" reflects the full history.
 * `null` means no cap — use everything.
 */
interface TrendWindow {
  readonly label: string
  readonly days: number | null
}

const TREND_WINDOWS: ReadonlyArray<TrendWindow> = [
  { label: '30d', days: 30 },
  { label: '60d', days: 60 },
  { label: '90d', days: 90 },
  { label: '180d', days: 180 },
  { label: '365d', days: 365 },
  { label: 'All', days: null },
]

const DAY_UNIT_BY_LOCALE: Record<string, string> = {
  fr: 'j',
}

function localizeWindowLabel(label: string, locale: string): string {
  const unit = DAY_UNIT_BY_LOCALE[locale.toLowerCase().slice(0, 2)]
  if (!unit) return label
  return label.replace(/d$/, unit)
}

const dateLabel = (ts: number, locale: string) =>
  new Date(ts).toLocaleDateString(locale, { month: 'short', year: '2-digit' })

const fullDateLabel = (ts: number, locale: string) => new Date(ts).toLocaleDateString(locale)

interface RegressionFit {
  slope: number
  intercept: number
}

/**
 * Ordinary least-squares fit for a series of (x, y) pairs. Used to draw a
 * single straight trend line through the whole patrimony history — "une
 * droite lissée" — that continues into the forecast range with the same
 * slope. We parametrise x in days so a forecast timestamp can be plugged
 * directly into the same `y = slope·x + intercept` formula regardless of
 * whether the chart data is daily, weekly, or monthly.
 */
function fitLinear(points: ReadonlyArray<{ x: number; y: number }>): RegressionFit | null {
  const n = points.length
  if (n < 2) return null
  let sumX = 0
  let sumY = 0
  let sumXY = 0
  let sumXX = 0
  for (const p of points) {
    sumX += p.x
    sumY += p.y
    sumXY += p.x * p.y
    sumXX += p.x * p.x
  }
  const denom = n * sumXX - sumX * sumX
  if (denom === 0) return null
  const slope = (n * sumXY - sumX * sumY) / denom
  const intercept = (sumY - slope * sumX) / n
  return { slope, intercept }
}

interface ChartPoint {
  /** Unix ms — the XAxis is numeric so history (daily) and forecast
   *  (monthly) render at their real calendar position. */
  ts: number
  balance: number | null
  /** Straight OLS trend value at this timestamp. */
  trend: number
  /** Lower edge of the deviation band: min(balance, trend). Null in forecast. */
  lower: number | null
  /** Balance above trend (ahead of savings pace). Null in forecast. */
  ahead: number | null
  /** Trend above balance (behind savings pace). Null in forecast. */
  behind: number | null
}

/**
 * Filter raw history to only the last {@link trendWindowDays} days. When
 * the window is null (= "All") we return the full series unchanged. This
 * is applied BEFORE {@link buildSeries} so the trend picker both narrows
 * the visible x-axis range and restricts regression/forecast inputs — the
 * user sees "zoom in on last 30d" instead of "show full history with a
 * trend line fit on the last 30d only".
 *
 * Falls back to the full series when filtering would leave fewer than 2
 * points — OLS needs at least two rows to compute a slope and Recharts
 * needs at least two points to draw the area.
 */
function filterVisibleData(
  data: ReadonlyArray<PatrimonyPoint>,
  trendWindowDays: number | null,
): ReadonlyArray<PatrimonyPoint> {
  if (trendWindowDays === null || data.length === 0) return data
  const lastHistoryTs = new Date(data[data.length - 1]?.date ?? '').getTime()
  const windowStartTs = lastHistoryTs - trendWindowDays * DAY_MS
  const filtered = data.filter((d) => new Date(d.date).getTime() >= windowStartTs)
  return filtered.length >= 2 ? filtered : data
}

interface BuiltSeries {
  points: ChartPoint[]
  /**
   * Net change per day over the visible window (OLS slope). Drives both the
   * headline "+X / mo" readout and the forecast extrapolation, so the
   * projected line literally matches the figure shown to the user. `null`
   * when there aren't enough points to fit a slope.
   */
  slopePerDay: number | null
}

/**
 * Net-worth change over the trailing calendar month: the latest balance minus
 * the balance as of the same calendar day one month earlier (carry-forward, so
 * a day with no recorded point uses the most recent prior balance). This is the
 * actual month the user lived — a stable figure that slides one day at a time —
 * rather than a residual against a fitted line, which was noisy and near
 * circular for day-to-day tracking. Computed from the FULL history, so it never
 * shifts with the trend-window picker. `null` when the series is empty or the
 * history doesn't reach back a full month (no baseline to compare against).
 */
function monthOverMonthGain(data: ReadonlyArray<PatrimonyPoint>): number | null {
  if (data.length === 0) return null
  const sorted = [...data].sort(
    (a, b) => new Date(a.date).getTime() - new Date(b.date).getTime(),
  )
  const last = sorted[sorted.length - 1]
  if (!last) return null
  const lastDate = new Date(last.date)
  // Same calendar day, previous month — clamp the day to the previous month's
  // length so e.g. 31 Mar maps to 28/29 Feb instead of rolling into March.
  const y = lastDate.getUTCFullYear()
  const m = lastDate.getUTCMonth()
  const daysInPrevMonth = new Date(Date.UTC(y, m, 0)).getUTCDate()
  const day = Math.min(lastDate.getUTCDate(), daysInPrevMonth)
  const targetTs = Date.UTC(y, m - 1, day)
  // Carry-forward: the balance in effect on the target date is the latest point
  // dated on or before it. Null baseline ⇒ the series starts after that date.
  let baseline: number | null = null
  for (const p of sorted) {
    if (new Date(p.date).getTime() <= targetTs) baseline = p.balance
    else break
  }
  if (baseline === null) return null
  return last.balance - baseline
}

/**
 * Build the series Recharts will render. The X-axis is a continuous time
 * scale (numeric Unix ms), so spacing is proportional: daily history points
 * sit close together and the 12-month forecast uses its real calendar share.
 *
 * The trend is a single straight OLS line over the visible window — its slope
 * is the average €/day saved, the one number the "+X / mo" readout shows and
 * the forecast extends. We also emit a signed deviation band: the gap between
 * the actual balance and that line, split into `ahead` (balance above the
 * average pace) and `behind` (below it), so the user reads at a glance when
 * they've been saving faster or slower than their own baseline.
 *
 * Input `data` is already filtered to the visible window (see
 * {@link filterVisibleData}), so everything reflects exactly what the user
 * sees and "the trend" changes with the scale they pick.
 */
function buildSeries(data: ReadonlyArray<PatrimonyPoint>, forecast: boolean): BuiltSeries {
  if (data.length === 0) return { points: [], slopePerDay: null }

  const firstTs = new Date(data[0]?.date ?? '').getTime()
  const lastTs = new Date(data[data.length - 1]?.date ?? '').getTime()

  // OLS straight-line fit over the visible window. This single line is the
  // trend — slope drives the readout and forecast, intercept anchors it.
  const fit = fitLinear(
    data.map((d) => ({
      x: (new Date(d.date).getTime() - firstTs) / DAY_MS,
      y: d.balance,
    })),
  )
  const slopePerDay = fit ? fit.slope : null
  const trendAt = (ts: number): number =>
    fit ? fit.intercept + fit.slope * ((ts - firstTs) / DAY_MS) : 0

  // Resample history to one point per day using carry-forward on balance, so
  // the tooltip lines up on whatever day the user points at (a sparse input —
  // e.g. a balance only every Sunday — would otherwise snap weekly).
  const sorted = [...data].sort(
    (a, b) => new Date(a.date).getTime() - new Date(b.date).getTime(),
  )
  let sortedIdx = 0
  let currentBalance = sorted[0]?.balance ?? 0
  const out: ChartPoint[] = []
  for (let ts = firstTs; ts <= lastTs; ts += DAY_MS) {
    while (
      sortedIdx < sorted.length &&
      new Date(sorted[sortedIdx]?.date ?? '').getTime() <= ts
    ) {
      currentBalance = sorted[sortedIdx]?.balance ?? currentBalance
      sortedIdx += 1
    }
    const trend = fit ? trendAt(ts) : currentBalance
    // Stacking lower → behind → ahead rebuilds the exact [min, max] envelope
    // between the two series per day, so only the gap is coloured.
    out.push({
      ts,
      balance: currentBalance,
      trend,
      lower: Math.min(currentBalance, trend),
      behind: Math.max(0, trend - currentBalance),
      ahead: Math.max(0, currentBalance - trend),
    })
  }

  if (!forecast || slopePerDay === null) {
    return { points: out, slopePerDay }
  }

  // Project the straight trend forward by whole calendar months. The band
  // stays null past today — there's no actual balance to deviate from yet.
  const lastDate = new Date(data[data.length - 1]?.date ?? '')
  for (let m = 1; m <= FORECAST_MONTHS; m++) {
    const future = new Date(
      Date.UTC(lastDate.getUTCFullYear(), lastDate.getUTCMonth() + m, lastDate.getUTCDate()),
    )
    const ts = future.getTime()
    out.push({ ts, balance: null, trend: trendAt(ts), lower: null, ahead: null, behind: null })
  }
  return { points: out, slopePerDay }
}

interface PatrimonyChartProps {
  data: PatrimonyPoint[]
  title?: string
  allHistoryLabel?: string
  showForecastLabel?: string
  hideForecastLabel?: string
}

export function PatrimonyChart({
  data,
  title = 'Patrimony',
  allHistoryLabel = 'All history',
  showForecastLabel = 'Show forecast',
  hideForecastLabel = 'Hide forecast',
}: PatrimonyChartProps) {
  const t = useT()
  const locale = useLocale()
  const allShort = t('dashboard.allShort', 'All')
  const trendLabel = t('dashboard.trend', 'Trend')
  const perMonthLabel = t('dashboard.perMonth', '/mo')
  const balanceLabel = t('dashboard.balance', 'Balance')
  const deviationLabel = t('dashboard.deviation', 'Deviation')
  const monthChangeLabel = t('dashboard.monthChange', 'Past month')
  const todayLabel = t('dashboard.today', 'today')
  const forecastedSuffix = t('dashboard.forecastedSuffix', ' · +12 months projected')
  const noDataYet = t('dashboard.noDataYet', 'No data yet.')
  const trendWindowAria = t('dashboard.trendLookbackWindow', 'Trend lookback window')
  const trendWindowLegend = t('dashboard.trendWindow', 'Trend window')
  const [forecast, setForecast] = useState(false)
  const [trendWindowIdx, setTrendWindowIdx] = useState(() =>
    TREND_WINDOWS.findIndex((w) => w.days === 365),
  )
  const shouldAnimate = usePlayOnce('dashboard:patrimony')
  const trendWindow = TREND_WINDOWS[trendWindowIdx] ?? TREND_WINDOWS[TREND_WINDOWS.length - 1]
  // Filter the raw history to the picked trend window BEFORE building the
  // series so both the visible area and the regression fit reflect the
  // same range. "All" returns data unchanged.
  const visibleData = useMemo(
    () => filterVisibleData(data, trendWindow?.days ?? null),
    [data, trendWindow?.days],
  )
  const { points: series, slopePerDay } = useMemo(
    () => buildSeries(visibleData, forecast),
    [visibleData, forecast],
  )
  // Actual net-worth change over the trailing calendar month (today vs the same
  // day last month), from the FULL history so it doesn't move with the trend
  // window. Replaces the old residual-against-the-fitted-line "deviation".
  const monthGain = useMemo(() => monthOverMonthGain(data), [data])
  // Headline trend figure: the visible window's slope expressed per month, so
  // the number changes with whatever scale the user is looking at.
  const slopePerMonth = slopePerDay !== null ? slopePerDay * DAYS_PER_MONTH : null
  const slopeTone =
    slopePerMonth === null || Math.abs(slopePerMonth) < 1
      ? 'text-muted-foreground'
      : slopePerMonth > 0
        ? 'text-emerald-600 dark:text-emerald-400'
        : 'text-destructive'
  // Trailing-month gain: growth reads as good (emerald), a drop as a warning
  // (destructive). Hidden when negligible or history is shorter than a month.
  const showMonthGain = monthGain !== null && Math.abs(monthGain) >= 1
  const monthGainTone =
    monthGain !== null && monthGain >= 0
      ? 'text-emerald-600 dark:text-emerald-400'
      : 'text-destructive'
  const lastRealTs =
    visibleData.length > 0
      ? new Date(visibleData[visibleData.length - 1]?.date ?? '').getTime()
      : null

  // Y-axis domain — start at the visible minimum (with a little headroom)
  // instead of 0. The default Recharts `[0, dataMax]` visually crushes the
  // variation: when balances hover around 14k€, a floor at 0 wastes the
  // bottom 60% of the plot area. Padding = 8% of the range (min 500€) so
  // the series never touches the top or bottom edge, then rounded to the
  // nearest 500€ so tick labels land on clean numbers.
  const balanceValues = visibleData.map((d) => d.balance)
  const trendValues = series.map((p) => p.trend)
  const allValues = [...balanceValues, ...trendValues]
  const rawMin = allValues.length > 0 ? Math.min(...allValues) : 0
  const rawMax = allValues.length > 0 ? Math.max(...allValues) : 0
  const range = rawMax - rawMin
  const pad = Math.max(range * 0.08, 500)
  const yMin = Math.floor((rawMin - pad) / 500) * 500
  const yMax = Math.ceil((rawMax + pad) / 500) * 500

  return (
    <Card
      className={
        shouldAnimate
          ? 'flex h-full flex-col animate-in fade-in-0 slide-in-from-bottom-2 duration-700'
          : 'flex h-full flex-col animate-in fade-in-0 duration-300'
      }
    >
      <CardHeader className="flex flex-row items-start justify-between gap-2 space-y-0 pb-2">
        <div className="min-w-0">
          <CardTitle className="text-sm font-medium">{title}</CardTitle>
          <p className="mt-0.5 text-[11px] text-muted-foreground">
            {trendWindow && trendWindow.days !== null
              ? t('dashboard.lastNd', { n: trendWindow.days }, `Last ${trendWindow.days}d`)
              : allHistoryLabel}
            {forecast ? forecastedSuffix : ''}
          </p>
          {slopePerMonth !== null && (
            <p className="mt-1 text-[11px] font-medium tabular-nums">
              <span className="text-muted-foreground">{trendLabel}: </span>
              <span className={slopeTone}>
                {formatCurrencySigned(slopePerMonth)} {perMonthLabel}
              </span>
            </p>
          )}
          {showMonthGain && (
            <p className="text-[11px] font-medium tabular-nums">
              <span className="text-muted-foreground">{monthChangeLabel}: </span>
              <span className={monthGainTone}>{formatCurrencySigned(monthGain as number)}</span>
            </p>
          )}
        </div>
        {data.length >= 2 && (
          <div className="flex flex-col items-end gap-1.5">
            <Button
              variant="ghost"
              size="sm"
              onClick={() => setForecast((v) => !v)}
              aria-pressed={forecast}
              className="h-7 px-2 text-[11px] font-medium text-muted-foreground hover:text-foreground"
            >
              {forecast ? hideForecastLabel : showForecastLabel}
            </Button>
            {/* Segmented picker for the trend lookback window. Small, no labels
                besides the days — the card subtitle explains what the series
                represents. Uses a real <fieldset> + <label> pair per radio so
                it stays keyboard-accessible without pulling in a UI kit. */}
            <fieldset
              className="flex items-center gap-0 rounded-md border border-border bg-background p-0.5 text-[10px]"
              aria-label={trendWindowAria}
            >
              <legend className="sr-only">{trendWindowLegend}</legend>
              {TREND_WINDOWS.map((w, idx) => {
                const active = idx === trendWindowIdx
                const label = w.days === null ? allShort : localizeWindowLabel(w.label, locale)
                return (
                  <label
                    key={w.label}
                    className={`cursor-pointer rounded px-1.5 py-0.5 font-medium transition-colors ${
                      active
                        ? 'bg-muted text-foreground'
                        : 'text-muted-foreground hover:text-foreground'
                    }`}
                  >
                    <input
                      type="radio"
                      name="trend-window"
                      className="sr-only"
                      checked={active}
                      onChange={() => setTrendWindowIdx(idx)}
                    />
                    {label}
                  </label>
                )
              })}
            </fieldset>
          </div>
        )}
      </CardHeader>
      <CardContent className="min-h-0 flex-1 pb-3">
        {data.length === 0 ? (
          <p className="text-sm text-muted-foreground">{noDataYet}</p>
        ) : (
          <NoSSR fallback={<div className="h-full w-full" />}>
            <ResponsiveContainer width="100%" height="100%">
              <ComposedChart data={series} margin={{ top: 10, right: 16, left: 0, bottom: 0 }}>
                <CartesianGrid strokeDasharray="3 3" stroke="var(--border)" />
                <XAxis
                  dataKey="ts"
                  type="number"
                  scale="time"
                  domain={['dataMin', 'dataMax']}
                  tickFormatter={(v: number) => dateLabel(v, locale)}
                  tickCount={6}
                  minTickGap={24}
                  stroke="var(--muted-foreground)"
                  tick={{ fontSize: 11, fill: 'var(--muted-foreground)' }}
                  axisLine={false}
                  tickLine={false}
                />
                <YAxis
                  domain={[yMin, yMax]}
                  allowDataOverflow={false}
                  tickFormatter={(v: number) => formatCurrencyCompact(v)}
                  stroke="var(--muted-foreground)"
                  tick={{ fontSize: 11, fill: 'var(--muted-foreground)' }}
                  axisLine={false}
                  tickLine={false}
                  width={56}
                />
                <Tooltip
                  cursor={{ stroke: 'var(--border)', strokeWidth: 1 }}
                  content={(props) => {
                    const { active, payload, label } = props as {
                      active?: boolean
                      label?: number | string
                      payload?: ReadonlyArray<{ dataKey?: string; value?: number | null }>
                    }
                    if (!active || !payload || payload.length === 0) return null
                    const bal = payload.find((p) => p.dataKey === 'balance')?.value
                    const tr = payload.find((p) => p.dataKey === 'trend')?.value
                    const dev = bal != null && tr != null ? Number(bal) - Number(tr) : null
                    const row = (lbl: string, val: string, color?: string) => (
                      <div style={{ display: 'flex', justifyContent: 'space-between', gap: 16 }}>
                        <span style={{ color: 'var(--muted-foreground)' }}>{lbl}</span>
                        <span style={{ fontVariantNumeric: 'tabular-nums', color }}>{val}</span>
                      </div>
                    )
                    return (
                      <div
                        style={{
                          borderRadius: 10,
                          background: 'var(--popover)',
                          border: '1px solid var(--border)',
                          color: 'var(--popover-foreground)',
                          fontSize: 12,
                          padding: '8px 10px',
                          boxShadow: '0 6px 24px -12px rgb(0 0 0 / 0.25)',
                        }}
                      >
                        <div style={{ color: 'var(--muted-foreground)', marginBottom: 4, fontSize: 11 }}>
                          {fullDateLabel(Number(label), locale)}
                        </div>
                        {bal != null && row(balanceLabel, formatCurrency(Number(bal)))}
                        {tr != null && row(trendLabel, formatCurrency(Number(tr)))}
                        {dev != null &&
                          row(
                            deviationLabel,
                            formatCurrencySigned(dev),
                            dev >= 0 ? '#10b981' : 'var(--destructive)',
                          )}
                      </div>
                    )
                  }}
                />
                {forecast && lastRealTs !== null && (
                  <ReferenceLine
                    x={lastRealTs}
                    stroke="var(--muted-foreground)"
                    strokeDasharray="2 2"
                    label={{
                      value: todayLabel,
                      position: 'insideTopRight',
                      fontSize: 10,
                      fill: 'var(--muted-foreground)',
                    }}
                  />
                )}
                {/* Deviation band: an invisible floor at min(balance, trend),
                    then the signed gap stacked on top — red when behind the
                    average pace, green when ahead. Stacking reconstructs the
                    exact envelope between the two series. */}
                <Area
                  type="linear"
                  dataKey="lower"
                  stackId="dev"
                  stroke="none"
                  fill="none"
                  fillOpacity={0}
                  isAnimationActive={false}
                  connectNulls={false}
                  dot={false}
                  activeDot={false}
                  legendType="none"
                />
                <Area
                  type="linear"
                  dataKey="behind"
                  stackId="dev"
                  stroke="none"
                  fill="var(--destructive)"
                  fillOpacity={0.16}
                  isAnimationActive={shouldAnimate}
                  animationDuration={1000}
                  connectNulls={false}
                  dot={false}
                  activeDot={false}
                  legendType="none"
                />
                <Area
                  type="linear"
                  dataKey="ahead"
                  stackId="dev"
                  stroke="none"
                  fill="#10b981"
                  fillOpacity={0.18}
                  isAnimationActive={shouldAnimate}
                  animationDuration={1000}
                  connectNulls={false}
                  dot={false}
                  activeDot={false}
                  legendType="none"
                />
                <Line
                  type="linear"
                  dataKey="trend"
                  stroke="var(--chart-3)"
                  strokeWidth={1.5}
                  strokeDasharray="5 4"
                  dot={false}
                  isAnimationActive={shouldAnimate}
                  animationBegin={300}
                  animationDuration={1100}
                  animationEasing="ease-out"
                />
                <Line
                  type="linear"
                  dataKey="balance"
                  stroke="var(--chart-1)"
                  strokeWidth={2}
                  dot={false}
                  connectNulls={false}
                  isAnimationActive={shouldAnimate}
                  animationDuration={1100}
                  animationEasing="ease-out"
                />
              </ComposedChart>
            </ResponsiveContainer>
          </NoSSR>
        )}
      </CardContent>
    </Card>
  )
}
