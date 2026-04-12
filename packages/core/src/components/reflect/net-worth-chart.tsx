'use client'

import { ArrowDownRight, ArrowUpRight } from 'lucide-react'
import {
  Area,
  AreaChart,
  CartesianGrid,
  ReferenceLine,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'
import { Card, CardContent, CardHeader, CardTitle } from '../ui/card'
import { cn } from '../../lib/utils'

interface NetWorthPoint {
  month: string
  cumulative: number
}

const formatEur = (v: number): string => `${Math.round(v).toLocaleString('fr-FR')} €`

const formatMonth = (m: string): string => {
  const [year, month] = m.split('-')
  if (!year || !month) return m
  const d = new Date(Number(year), Number(month) - 1, 1)
  return d.toLocaleDateString('fr-FR', { month: 'short', year: '2-digit' })
}

/**
 * Reflect — long-term Net worth trajectory.
 *
 * Design notes (previous version was an ugly hardcoded-blue area chart):
 *   - Colors come from the theme tokens (`--chart-1`, `--muted-foreground`,
 *     etc.) so light and dark modes both look native.
 *   - The headline area shows the *current* value plus a Δ vs. the oldest
 *     point in the window — so the user can read "my net worth grew 3.2k
 *     over 24 months" at a glance without squinting at the y-axis.
 *   - Start / min / max reference lines give a sense of scale without
 *     drowning the chart in gridlines.
 *   - Grid is subtle horizontal only, no dashed lines.
 *   - Y axis is dropped entirely because the headline + tooltip already
 *     carry the absolute values; the shape of the curve is what matters.
 */
export function NetWorthChart({ data }: { data: ReadonlyArray<NetWorthPoint> }) {
  const points = [...data]
  const first = points[0]?.cumulative ?? 0
  const last = points[points.length - 1]?.cumulative ?? 0
  const delta = last - first
  const deltaPct = first !== 0 ? (delta / Math.abs(first)) * 100 : 0
  const up = delta >= 0

  const values = points.map((p) => p.cumulative)
  const min = values.length ? Math.min(...values) : 0
  const max = values.length ? Math.max(...values) : 0

  return (
    <Card className="flex h-full flex-col">
      <CardHeader className="flex flex-row items-start justify-between gap-2 pb-1">
        <div className="min-w-0">
          <CardTitle className="text-xs uppercase tracking-wide text-muted-foreground">
            Net worth
          </CardTitle>
          <p className="mt-1 text-2xl font-bold tabular-nums">{formatEur(last)}</p>
        </div>
        <div
          className={cn(
            'mt-0.5 flex items-center gap-1 rounded-full px-2 py-0.5 text-[11px] font-medium tabular-nums',
            up
              ? 'bg-emerald-500/10 text-emerald-600 dark:text-emerald-400'
              : 'bg-destructive/10 text-destructive',
          )}
        >
          {up ? <ArrowUpRight className="h-3 w-3" /> : <ArrowDownRight className="h-3 w-3" />}
          <span>
            {up ? '+' : ''}
            {formatEur(delta)}
          </span>
          <span className="opacity-70">
            ({up ? '+' : ''}
            {deltaPct.toFixed(0)}%)
          </span>
        </div>
      </CardHeader>
      <CardContent className="min-h-0 flex-1 pb-3">
        <ResponsiveContainer width="100%" height="100%" minHeight={140}>
          <AreaChart data={points} margin={{ top: 8, right: 8, left: 8, bottom: 0 }}>
            <defs>
              <linearGradient id="nwGrad" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor="var(--chart-1)" stopOpacity={0.5} />
                <stop offset="100%" stopColor="var(--chart-1)" stopOpacity={0} />
              </linearGradient>
            </defs>
            <CartesianGrid vertical={false} stroke="var(--border)" strokeOpacity={0.6} />
            <XAxis
              dataKey="month"
              tickFormatter={formatMonth}
              tick={{ fontSize: 10, fill: 'var(--muted-foreground)' }}
              axisLine={false}
              tickLine={false}
              minTickGap={24}
            />
            <YAxis hide domain={['dataMin - 500', 'dataMax + 500']} />
            <Tooltip
              cursor={{ stroke: 'var(--chart-1)', strokeOpacity: 0.4, strokeWidth: 1 }}
              contentStyle={{
                borderRadius: 8,
                background: 'var(--popover)',
                border: '1px solid var(--border)',
                fontSize: 12,
                color: 'var(--popover-foreground)',
              }}
              formatter={(value) => [formatEur(Number(value)), 'Net worth']}
              labelFormatter={(label) => formatMonth(String(label))}
            />
            <ReferenceLine
              y={first}
              stroke="var(--muted-foreground)"
              strokeOpacity={0.4}
              strokeDasharray="2 4"
              label={{
                value: `start ${formatEur(first)}`,
                position: 'insideTopLeft',
                fontSize: 9,
                fill: 'var(--muted-foreground)',
              }}
            />
            <Area
              type="monotone"
              dataKey="cumulative"
              stroke="var(--chart-1)"
              strokeWidth={2.5}
              fill="url(#nwGrad)"
              isAnimationActive={false}
              activeDot={{ r: 4, strokeWidth: 0, fill: 'var(--chart-1)' }}
            />
          </AreaChart>
        </ResponsiveContainer>
        <div className="mt-2 flex items-center justify-between text-[10px] text-muted-foreground tabular-nums">
          <span>min {formatEur(min)}</span>
          <span>{points.length} months</span>
          <span>max {formatEur(max)}</span>
        </div>
      </CardContent>
    </Card>
  )
}
