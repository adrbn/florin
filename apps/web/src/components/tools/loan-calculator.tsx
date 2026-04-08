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
import { calculateLoan } from '@/lib/calculators/loan'
import { formatCurrency } from '@/lib/format/currency'

const formatEur = (v: number): string => `${Math.round(v).toLocaleString('fr-FR')} €`

/**
 * Loan calculator — interactive form on the left, amortization chart on
 * the right. Inputs are local state so the chart updates as the user types.
 */
export function LoanCalculator() {
  const [principal, setPrincipal] = useState(200_000)
  const [rate, setRate] = useState(3.5)
  const [years, setYears] = useState(20)

  const summary = useMemo(
    () => calculateLoan({ principal, annualRatePct: rate, years }),
    [principal, rate, years],
  )

  // Sample one row per year for the chart so 30y mortgages don't render
  // 360 ticks. Always include the final month.
  const chartData = useMemo(() => {
    const samples = summary.schedule.filter((e) => e.month % 12 === 0)
    const last = summary.schedule[summary.schedule.length - 1]
    if (last && samples[samples.length - 1] !== last) samples.push(last)
    return samples.map((e) => ({
      year: (e.month / 12).toFixed(1),
      remaining: Math.round(e.remaining),
      paidPrincipal: Math.round(principal - e.remaining),
    }))
  }, [summary, principal])

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Loan calculator</CardTitle>
      </CardHeader>
      <CardContent>
        <div className="grid gap-6 lg:grid-cols-[280px_minmax(0,1fr)]">
          <form className="space-y-3" onSubmit={(e) => e.preventDefault()}>
            <div className="space-y-1.5">
              <Label htmlFor="loan-principal">Principal (EUR)</Label>
              <Input
                id="loan-principal"
                type="number"
                step="1000"
                min="0"
                value={principal}
                onChange={(e) => setPrincipal(Number(e.target.value))}
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="loan-rate">Annual rate (%)</Label>
              <Input
                id="loan-rate"
                type="number"
                step="0.05"
                min="0"
                value={rate}
                onChange={(e) => setRate(Number(e.target.value))}
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="loan-years">Years</Label>
              <Input
                id="loan-years"
                type="number"
                step="1"
                min="1"
                value={years}
                onChange={(e) => setYears(Number(e.target.value))}
              />
            </div>

            <div className="space-y-1 rounded-md border border-border bg-muted/40 p-3 text-xs">
              <p className="flex justify-between">
                <span className="text-muted-foreground">Monthly payment</span>
                <span className="font-mono font-semibold text-foreground">
                  {formatCurrency(summary.monthlyPayment)}
                </span>
              </p>
              <p className="flex justify-between">
                <span className="text-muted-foreground">Total paid</span>
                <span className="font-mono text-foreground">
                  {formatCurrency(summary.totalPaid)}
                </span>
              </p>
              <p className="flex justify-between">
                <span className="text-muted-foreground">Total interest</span>
                <span className="font-mono text-destructive">
                  {formatCurrency(summary.totalInterest)}
                </span>
              </p>
            </div>
          </form>

          <div className="min-h-[320px]">
            <ResponsiveContainer width="100%" height={320}>
              <AreaChart data={chartData} margin={{ top: 10, right: 16, left: 0, bottom: 0 }}>
                <defs>
                  <linearGradient id="loanRem" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%" stopColor="#ef4444" stopOpacity={0.45} />
                    <stop offset="100%" stopColor="#ef4444" stopOpacity={0} />
                  </linearGradient>
                  <linearGradient id="loanPaid" x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%" stopColor="#10b981" stopOpacity={0.45} />
                    <stop offset="100%" stopColor="#10b981" stopOpacity={0} />
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
                  dataKey="remaining"
                  name="Remaining"
                  stroke="#ef4444"
                  fill="url(#loanRem)"
                  strokeWidth={2}
                  isAnimationActive={false}
                />
                <Area
                  type="monotone"
                  dataKey="paidPrincipal"
                  name="Principal paid"
                  stroke="#10b981"
                  fill="url(#loanPaid)"
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
