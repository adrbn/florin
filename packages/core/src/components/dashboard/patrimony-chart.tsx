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
import { formatCurrency } from '../../lib/format/currency'

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

const dateLabel = (ts: number) =>
  new Date(ts).toLocaleDateString('fr-FR', { month: 'short', year: '2-digit' })

const fullDateLabel = (ts: number) => new Date(ts).toLocaleDateString('fr-FR')

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
  trend: number
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

/**
 * Build the series Recharts will render. The X-axis is a continuous time
 * scale (numeric Unix ms), so we get proportional spacing automatically:
 * daily history points sit close together and the 12-month forecast uses
 * its actual calendar share of the axis — no more "12 forecast points
 * compressed next to 100 history points" glitch.
 *
 * Input `data` is already filtered to the visible window (see
 * {@link filterVisibleData}), so regression is fit on exactly what the
 * user sees and the forecast extends from the last visible point.
 */
function buildSeries(data: ReadonlyArray<PatrimonyPoint>, forecast: boolean): ChartPoint[] {
  if (data.length === 0) return []

  // Linear-regression fit over the visible window → a single straight line
  // (in day space) that we then evaluate at every history and forecast
  // point. Rendered as one clean line across both ranges.
  const firstTs = new Date(data[0]?.date ?? '').getTime()
  const lastTs = new Date(data[data.length - 1]?.date ?? '').getTime()
  const points = data.map((d) => ({
    x: (new Date(d.date).getTime() - firstTs) / DAY_MS,
    y: d.balance,
  }))
  const fit = fitLinear(points) ?? { slope: 0, intercept: data[0]?.balance ?? 0 }
  const trendAt = (ts: number) => fit.intercept + fit.slope * ((ts - firstTs) / DAY_MS)

  // Resample history to one point per day using carry-forward on balance.
  // Without this, a sparse input (e.g. a balance only every Sunday) makes
  // the Recharts tooltip snap weekly instead of daily — so hovering
  // Tuesday shows Sunday's value. With a per-day series the hover cursor
  // lines up on whatever day the user is pointing at.
  const out: ChartPoint[] = []
  const sorted = [...data].sort(
    (a, b) => new Date(a.date).getTime() - new Date(b.date).getTime(),
  )
  let sortedIdx = 0
  let currentBalance = sorted[0]?.balance ?? 0
  for (let ts = firstTs; ts <= lastTs; ts += DAY_MS) {
    while (
      sortedIdx < sorted.length &&
      new Date(sorted[sortedIdx]?.date ?? '').getTime() <= ts
    ) {
      currentBalance = sorted[sortedIdx]?.balance ?? currentBalance
      sortedIdx += 1
    }
    out.push({ ts, balance: currentBalance, trend: trendAt(ts) })
  }

  if (!forecast) return out

  // Extend forward by whole calendar months (not "30 days * m") so the
  // ticks come out clean: April → May → June → … → April next year.
  // The "ms * m" approach drifted because months aren't uniform in length.
  const last = data[data.length - 1]
  if (!last) return out
  const lastDate = new Date(last.date)
  for (let m = 1; m <= FORECAST_MONTHS; m++) {
    const future = new Date(
      Date.UTC(lastDate.getUTCFullYear(), lastDate.getUTCMonth() + m, lastDate.getUTCDate()),
    )
    const ts = future.getTime()
    out.push({ ts, balance: null, trend: trendAt(ts) })
  }
  return out
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
  const balanceLabel = t('dashboard.balance', 'Balance')
  const todayLabel = t('dashboard.today', 'today')
  const forecastedSuffix = t('dashboard.forecastedSuffix', ' · +12 months projected')
  const noDataYet = t('dashboard.noDataYet', 'No data yet.')
  const trendWindowAria = t('dashboard.trendLookbackWindow', 'Trend lookback window')
  const trendWindowLegend = t('dashboard.trendWindow', 'Trend window')
  const [forecast, setForecast] = useState(false)
  const [trendWindowIdx, setTrendWindowIdx] = useState(() =>
    TREND_WINDOWS.findIndex((w) => w.days === null),
  )
  const trendWindow = TREND_WINDOWS[trendWindowIdx] ?? TREND_WINDOWS[TREND_WINDOWS.length - 1]
  // Filter the raw history to the picked trend window BEFORE building the
  // series so both the visible area and the regression fit reflect the
  // same range. "All" returns data unchanged.
  const visibleData = useMemo(
    () => filterVisibleData(data, trendWindow?.days ?? null),
    [data, trendWindow?.days],
  )
  const series = useMemo(() => buildSeries(visibleData, forecast), [visibleData, forecast])
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
    <Card className="flex h-full flex-col">
      <CardHeader className="flex flex-row items-start justify-between gap-2 space-y-0 pb-2">
        <div className="min-w-0">
          <CardTitle className="text-sm font-medium">{title}</CardTitle>
          <p className="mt-0.5 text-[11px] text-muted-foreground">
            {trendWindow && trendWindow.days !== null
              ? t('dashboard.lastNd', { n: trendWindow.days }, `Last ${trendWindow.days}d`)
              : allHistoryLabel}
            {forecast ? forecastedSuffix : ''}
          </p>
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
                <defs>
                  <linearGradient id="patriGrad" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%" stopColor="var(--chart-1)" stopOpacity={0.32} />
                    <stop offset="100%" stopColor="var(--chart-1)" stopOpacity={0} />
                  </linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="3 3" stroke="var(--border)" />
                <XAxis
                  dataKey="ts"
                  type="number"
                  scale="time"
                  domain={['dataMin', 'dataMax']}
                  tickFormatter={(v: number) => dateLabel(v)}
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
                  tickFormatter={(v: number) => `${(v / 1000).toFixed(1)}k €`}
                  stroke="var(--muted-foreground)"
                  tick={{ fontSize: 11, fill: 'var(--muted-foreground)' }}
                  axisLine={false}
                  tickLine={false}
                  width={56}
                />
                <Tooltip
                  cursor={{ stroke: 'var(--border)', strokeWidth: 1 }}
                  contentStyle={{
                    borderRadius: 10,
                    background: 'var(--popover)',
                    border: '1px solid var(--border)',
                    color: 'var(--popover-foreground)',
                    fontSize: 12,
                    padding: '8px 10px',
                    boxShadow: '0 6px 24px -12px rgb(0 0 0 / 0.25)',
                  }}
                  labelStyle={{
                    color: 'var(--muted-foreground)',
                    marginBottom: 4,
                    fontSize: 11,
                  }}
                  itemStyle={{ color: 'var(--popover-foreground)' }}
                  labelFormatter={(label) => fullDateLabel(Number(label))}
                  formatter={(value, name) => [
                    formatCurrency(Number(value)),
                    name === 'trend' ? trendLabel : balanceLabel,
                  ]}
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
                <Area
                  type="monotone"
                  dataKey="balance"
                  stroke="var(--chart-1)"
                  strokeWidth={2}
                  fill="url(#patriGrad)"
                  baseValue={yMin}
                  isAnimationActive
                  animationDuration={1200}
                  animationEasing="ease-out"
                  connectNulls={false}
                  dot={false}
                />
                <Line
                  type="linear"
                  dataKey="trend"
                  stroke="var(--chart-3)"
                  strokeWidth={1.5}
                  strokeDasharray="4 4"
                  dot={false}
                  isAnimationActive
                  animationBegin={400}
                  animationDuration={1200}
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
