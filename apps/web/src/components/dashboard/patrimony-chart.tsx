'use client'

import { useState } from 'react'
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
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { NoSSR } from '@/components/ui/no-ssr'
import { formatCurrency } from '@/lib/format/currency'

export interface PatrimonyPoint {
  date: string
  balance: number
}

const FORECAST_MONTHS = 12
const DAY_MS = 24 * 60 * 60 * 1000

const dateLabel = (ts: number) =>
  new Date(ts).toLocaleDateString('fr-FR', { month: 'short', year: '2-digit' })

const fullDateLabel = (ts: number) => new Date(ts).toLocaleDateString('fr-FR')

interface RegressionFit {
  slope: number
  intercept: number
}

/**
 * Linear-regression fit for a series of y values indexed by position
 * (0, 1, 2, …). Used only for the forecast portion, where we extrapolate
 * forward from the last EWMA point using the slope of the most recent
 * history window. The per-index slope is treated as a per-day slope since
 * snapshots land on consecutive days.
 */
function fitLinear(values: ReadonlyArray<number>): RegressionFit | null {
  const n = values.length
  if (n < 2) return null
  let sumX = 0
  let sumY = 0
  let sumXY = 0
  let sumXX = 0
  for (let i = 0; i < n; i++) {
    const value = values[i] ?? 0
    sumX += i
    sumY += value
    sumXY += i * value
    sumXX += i * i
  }
  const denom = n * sumXX - sumX * sumX
  if (denom === 0) return null
  const slope = (n * sumXY - sumX * sumY) / denom
  const intercept = (sumY - slope * sumX) / n
  return { slope, intercept }
}

/**
 * Exponentially-weighted moving average of `values`. alpha ≈ 0.12 gives
 * ~16-point effective window — strong enough to kill day-to-day jitter,
 * loose enough that the curve still tracks real shifts in balance
 * (salary, big outflows) rather than lagging comically behind them.
 * The first sample is seeded with the raw value so the curve starts on
 * the data instead of at zero.
 */
function ewma(values: ReadonlyArray<number>, alpha = 0.12): number[] {
  const out: number[] = []
  let s = values[0] ?? 0
  for (let i = 0; i < values.length; i++) {
    const v = values[i] ?? 0
    s = i === 0 ? v : alpha * v + (1 - alpha) * s
    out.push(s)
  }
  return out
}

/** Slope (per index) of the last `lookback` history points — used to project
 *  the smoothed trend into the forecast range without baking in noise from
 *  old months that no longer reflect the current trajectory. */
function recentSlope(values: ReadonlyArray<number>, lookback = 60): number {
  if (values.length < 2) return 0
  const slice = values.slice(-Math.min(lookback, values.length))
  const fit = fitLinear(slice)
  return fit?.slope ?? 0
}

interface ChartPoint {
  /** Unix ms — the XAxis is numeric so history (daily) and forecast
   *  (monthly) render at their real calendar position. */
  ts: number
  balance: number | null
  trend: number
}

/**
 * Build the series Recharts will render. The X-axis is a continuous time
 * scale (numeric Unix ms), so we get proportional spacing automatically:
 * daily history points sit close together and the 12-month forecast uses
 * its actual calendar share of the axis — no more "12 forecast points
 * compressed next to 100 history points" glitch.
 */
function buildSeries(data: ReadonlyArray<PatrimonyPoint>, forecast: boolean): ChartPoint[] {
  if (data.length === 0) return []

  // Smoothed history trend: EWMA of the balance series, so the curve
  // tracks the actual evolution of the patrimony instead of flattening
  // it into a single regression line. Forecast continues linearly from
  // the last EWMA value using the slope of the last ~60 days so it
  // reflects the user's current trajectory, not the average of the
  // whole year.
  const rawValues = data.map((d) => d.balance)
  const smoothed = ewma(rawValues)
  const slope = recentSlope(rawValues)
  const lastSmoothed = smoothed[smoothed.length - 1] ?? 0

  const out: ChartPoint[] = data.map((point, i) => ({
    ts: new Date(point.date).getTime(),
    balance: point.balance,
    trend: smoothed[i] ?? point.balance,
  }))

  if (!forecast) return out

  // Extend forward by whole calendar months (not "30 days * m") so the
  // ticks come out clean: April → May → June → … → April next year.
  // The "ms * m" approach drifted because months aren't uniform in length.
  const last = data[data.length - 1]
  if (!last) return out
  const lastDate = new Date(last.date)
  const spanDays = Math.max(
    1,
    (new Date(last.date).getTime() - new Date(data[0]?.date ?? last.date).getTime()) / DAY_MS,
  )
  const indexPerDay = (data.length - 1) / spanDays
  for (let m = 1; m <= FORECAST_MONTHS; m++) {
    const future = new Date(
      Date.UTC(lastDate.getUTCFullYear(), lastDate.getUTCMonth() + m, lastDate.getUTCDate()),
    )
    const daysAhead = (future.getTime() - new Date(last.date).getTime()) / DAY_MS
    const indicesAhead = daysAhead * indexPerDay
    out.push({
      ts: future.getTime(),
      balance: null,
      trend: lastSmoothed + slope * indicesAhead,
    })
  }
  return out
}

export function PatrimonyChart({ data }: { data: PatrimonyPoint[] }) {
  const [forecast, setForecast] = useState(false)
  const series = buildSeries(data, forecast)
  const lastRealTs = data.length > 0 ? new Date(data[data.length - 1]?.date ?? '').getTime() : null

  // Y-axis domain — start at the historical minimum (with a little headroom)
  // instead of 0. The default Recharts `[0, dataMax]` visually crushes the
  // variation: when balances hover around 14k€, a floor at 0 wastes the
  // bottom 60% of the plot area. Padding = 8% of the range (min 500€) so
  // the series never touches the top or bottom edge, then rounded to the
  // nearest 500€ so tick labels land on clean numbers.
  const balanceValues = data.map((d) => d.balance)
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
      <CardHeader className="flex flex-row items-center justify-between gap-2 space-y-0 pb-2">
        <div className="min-w-0">
          <CardTitle className="text-sm font-medium">Patrimony</CardTitle>
          <p className="mt-0.5 text-[11px] text-muted-foreground">
            Last 12 months{forecast ? ' · +12 months projected' : ''}
          </p>
        </div>
        {data.length >= 2 && (
          <Button
            variant="ghost"
            size="sm"
            onClick={() => setForecast((v) => !v)}
            aria-pressed={forecast}
            className="h-7 px-2 text-[11px] font-medium text-muted-foreground hover:text-foreground"
          >
            {forecast ? 'Hide forecast' : 'Show forecast'}
          </Button>
        )}
      </CardHeader>
      <CardContent className="min-h-0 flex-1 pb-3">
        {data.length === 0 ? (
          <p className="text-sm text-muted-foreground">No data yet.</p>
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
                    name === 'trend' ? 'Trend' : 'Balance',
                  ]}
                />
                {forecast && lastRealTs !== null && (
                  <ReferenceLine
                    x={lastRealTs}
                    stroke="var(--muted-foreground)"
                    strokeDasharray="2 2"
                    label={{
                      value: 'today',
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
                  isAnimationActive={false}
                  connectNulls={false}
                  dot={false}
                />
                <Line
                  type="monotone"
                  dataKey="trend"
                  stroke="var(--chart-3)"
                  strokeWidth={1.5}
                  strokeDasharray="4 4"
                  dot={false}
                  isAnimationActive={false}
                />
              </ComposedChart>
            </ResponsiveContainer>
          </NoSSR>
        )}
      </CardContent>
    </Card>
  )
}
