'use client'

import { useMemo, useState } from 'react'
import {
  Area,
  AreaChart,
  CartesianGrid,
  Legend,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { calculateCompound } from '@/lib/calculators/compound'
import { formatCurrency } from '@/lib/format/currency'

const formatEur = (v: number): string => `${Math.round(v).toLocaleString('fr-FR')} €`

/**
 * Compound interest calculator. Renders an exponential-looking area chart
 * stacking total contributions vs interest accrued so the user can see
 * the magic of compounding visually.
 */
export function CompoundCalculator() {
  const [initial, setInitial] = useState(10_000)
  const [monthly, setMonthly] = useState(500)
  const [rate, setRate] = useState(7)
  const [years, setYears] = useState(25)

  const summary = useMemo(
    () =>
      calculateCompound({
        initial,
        monthlyContribution: monthly,
        annualRatePct: rate,
        years,
      }),
    [initial, monthly, rate, years],
  )

  const chartData = useMemo(
    () =>
      summary.series
        .filter((p) => p.month % 12 === 0)
        .map((p) => ({
          year: (p.month / 12).toFixed(0),
          contributed: Math.round(p.contributed),
          interest: Math.round(p.interest),
        })),
    [summary],
  )

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Compound interest calculator</CardTitle>
      </CardHeader>
      <CardContent>
        <div className="grid gap-6 lg:grid-cols-[280px_minmax(0,1fr)]">
          <form className="space-y-3" onSubmit={(e) => e.preventDefault()}>
            <div className="space-y-1.5">
              <Label htmlFor="ci-initial">Initial deposit (EUR)</Label>
              <Input
                id="ci-initial"
                type="number"
                step="100"
                min="0"
                value={initial}
                onChange={(e) => setInitial(Number(e.target.value))}
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="ci-monthly">Monthly contribution (EUR)</Label>
              <Input
                id="ci-monthly"
                type="number"
                step="50"
                min="0"
                value={monthly}
                onChange={(e) => setMonthly(Number(e.target.value))}
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="ci-rate">Annual return (%)</Label>
              <Input
                id="ci-rate"
                type="number"
                step="0.1"
                value={rate}
                onChange={(e) => setRate(Number(e.target.value))}
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="ci-years">Years</Label>
              <Input
                id="ci-years"
                type="number"
                step="1"
                min="1"
                value={years}
                onChange={(e) => setYears(Number(e.target.value))}
              />
            </div>

            <div className="space-y-1 rounded-md border border-border bg-muted/40 p-3 text-xs">
              <p className="flex justify-between">
                <span className="text-muted-foreground">Final balance</span>
                <span className="font-mono font-semibold text-emerald-600 dark:text-emerald-400">
                  {formatCurrency(summary.finalBalance)}
                </span>
              </p>
              <p className="flex justify-between">
                <span className="text-muted-foreground">Contributed</span>
                <span className="font-mono text-foreground">
                  {formatCurrency(summary.totalContributed)}
                </span>
              </p>
              <p className="flex justify-between">
                <span className="text-muted-foreground">Interest earned</span>
                <span className="font-mono text-amber-600 dark:text-amber-400">
                  {formatCurrency(summary.totalInterest)}
                </span>
              </p>
            </div>
          </form>

          <div className="min-h-[320px]">
            <ResponsiveContainer width="100%" height={320}>
              <AreaChart data={chartData} margin={{ top: 10, right: 16, left: 0, bottom: 0 }}>
                <defs>
                  <linearGradient id="ciContrib" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%" stopColor="#3b82f6" stopOpacity={0.55} />
                    <stop offset="100%" stopColor="#3b82f6" stopOpacity={0.05} />
                  </linearGradient>
                  <linearGradient id="ciInt" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%" stopColor="#f59e0b" stopOpacity={0.55} />
                    <stop offset="100%" stopColor="#f59e0b" stopOpacity={0.05} />
                  </linearGradient>
                </defs>
                <CartesianGrid strokeDasharray="3 3" className="stroke-muted" />
                <XAxis dataKey="year" className="text-xs" />
                <YAxis
                  tickFormatter={(v: number) => `${(v / 1000).toFixed(0)}k`}
                  className="text-xs"
                  width={48}
                />
                <Tooltip
                  contentStyle={{
                    borderRadius: 8,
                    background: 'hsl(var(--popover))',
                    border: '1px solid hsl(var(--border))',
                  }}
                  formatter={(value, name) => [formatEur(Number(value)), String(name)]}
                  labelFormatter={(label) => `Year ${label}`}
                />
                <Legend wrapperStyle={{ fontSize: 11 }} />
                <Area
                  type="monotone"
                  stackId="1"
                  dataKey="contributed"
                  name="Contributed"
                  stroke="#3b82f6"
                  fill="url(#ciContrib)"
                  strokeWidth={2}
                  isAnimationActive={false}
                />
                <Area
                  type="monotone"
                  stackId="1"
                  dataKey="interest"
                  name="Interest"
                  stroke="#f59e0b"
                  fill="url(#ciInt)"
                  strokeWidth={2}
                  isAnimationActive={false}
                />
              </AreaChart>
            </ResponsiveContainer>
          </div>
        </div>
      </CardContent>
    </Card>
  )
}
