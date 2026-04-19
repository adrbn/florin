'use client'

import {
  Bar,
  BarChart,
  CartesianGrid,
  Legend,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'
import { Card, CardContent, CardHeader, CardTitle } from '../ui/card'
import { NoSSR } from '../ui/no-ssr'
import { formatCurrency } from '../../lib/format/currency'

export interface MonthlyFlow {
  month: string // YYYY-MM
  income: number
  expense: number
  net: number
}

const formatMonth = (m: string): string => {
  const [year, month] = m.split('-')
  if (!year || !month) return m
  const d = new Date(Number(year), Number(month) - 1, 1)
  return d.toLocaleDateString('fr-FR', { month: 'short' })
}

/**
 * Dashboard version of the income-vs-spending bar chart. Fills its flex
 * parent (no hard-coded height) and uses the same tooltip / axis styling
 * as the patrimony and category pie cards so the dashboard reads as one
 * coherent surface rather than a patchwork.
 */
interface IncomeVsSpendingCardProps {
  data: ReadonlyArray<MonthlyFlow>
  title?: string
  subtitle?: string
}

export function IncomeVsSpendingCard({
  data,
  title = 'Income vs spending',
  subtitle = 'Last 12 months',
}: IncomeVsSpendingCardProps) {
  const hasData = data.some((d) => d.income > 0 || d.expense > 0)
  return (
    <Card className="flex h-full flex-col">
      <CardHeader className="pb-2">
        <CardTitle className="text-sm font-medium">{title}</CardTitle>
        <p className="mt-0.5 text-[11px] text-muted-foreground">{subtitle}</p>
      </CardHeader>
      <CardContent className="min-h-0 flex-1 pb-3">
        {!hasData ? (
          <p className="text-xs text-muted-foreground">No activity yet.</p>
        ) : (
          <NoSSR fallback={<div className="h-full w-full" />}>
            <ResponsiveContainer width="100%" height="100%">
              <BarChart
                data={[...data]}
                margin={{ top: 10, right: 16, left: 0, bottom: 0 }}
                barCategoryGap="20%"
              >
                <CartesianGrid strokeDasharray="3 3" stroke="var(--border)" />
                <XAxis
                  dataKey="month"
                  tickFormatter={formatMonth}
                  stroke="var(--muted-foreground)"
                  tick={{ fontSize: 11, fill: 'var(--muted-foreground)' }}
                  axisLine={false}
                  tickLine={false}
                />
                <YAxis
                  tickFormatter={(v: number) => `${(v / 1000).toFixed(0)}k`}
                  stroke="var(--muted-foreground)"
                  tick={{ fontSize: 11, fill: 'var(--muted-foreground)' }}
                  axisLine={false}
                  tickLine={false}
                  width={44}
                />
                <Tooltip
                  cursor={{ fill: 'var(--muted)', opacity: 0.35 }}
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
                  formatter={(value, name) => [formatCurrency(Number(value)), String(name)]}
                  labelFormatter={(label) => formatMonth(String(label))}
                />
                <Legend
                  wrapperStyle={{ fontSize: 11, paddingTop: 4 }}
                  iconType="circle"
                  iconSize={8}
                />
                <Bar dataKey="income" name="Income" fill="#10b981" radius={[3, 3, 0, 0]} />
                <Bar dataKey="expense" name="Spending" fill="#ef4444" radius={[3, 3, 0, 0]} />
              </BarChart>
            </ResponsiveContainer>
          </NoSSR>
        )}
      </CardContent>
    </Card>
  )
}
