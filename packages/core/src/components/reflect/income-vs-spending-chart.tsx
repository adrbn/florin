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
import { useLocale } from '../../i18n/context'
import { formatCurrency } from '../../lib/format/currency'

interface MonthlyFlow {
  month: string
  income: number
  expense: number
  net: number
}

const formatEur = (v: number): string => formatCurrency(Math.round(v))

const formatMonth = (m: string, locale: string): string => {
  const [year, month] = m.split('-')
  if (!year || !month) return m
  const d = new Date(Number(year), Number(month) - 1, 1)
  return d.toLocaleDateString(locale, { month: 'short' })
}

interface IncomeVsSpendingChartProps {
  data: ReadonlyArray<MonthlyFlow>
  title?: string
  incomeLabel?: string
  spendingLabel?: string
}

export function IncomeVsSpendingChart({
  data,
  title = 'Income vs spending',
  incomeLabel = 'Income',
  spendingLabel = 'Spending',
}: IncomeVsSpendingChartProps) {
  const locale = useLocale()
  return (
    <Card className="flex h-full flex-col">
      <CardHeader className="pb-1">
        <CardTitle className="text-xs uppercase tracking-wide text-muted-foreground">
          {title}
        </CardTitle>
      </CardHeader>
      <CardContent className="min-h-0 flex-1 pb-3">
        <ResponsiveContainer width="100%" height="100%" minHeight={140}>
          <BarChart data={[...data]} margin={{ top: 10, right: 8, left: -8, bottom: 0 }}>
            <CartesianGrid vertical={false} stroke="var(--border)" strokeOpacity={0.6} />
            <XAxis
              dataKey="month"
              tickFormatter={(m: string) => formatMonth(m, locale)}
              tick={{ fontSize: 10, fill: 'var(--muted-foreground)' }}
              axisLine={false}
              tickLine={false}
              minTickGap={16}
            />
            <YAxis
              tickFormatter={(v: number) => `${(v / 1000).toFixed(0)}k`}
              tick={{ fontSize: 10, fill: 'var(--muted-foreground)' }}
              axisLine={false}
              tickLine={false}
              width={36}
            />
            <Tooltip
              cursor={{ fill: 'var(--muted)', opacity: 0.3 }}
              contentStyle={{
                borderRadius: 8,
                background: 'var(--popover)',
                border: '1px solid var(--border)',
                fontSize: 12,
                color: 'var(--popover-foreground)',
              }}
              formatter={(value, name) => [formatEur(Number(value)), String(name)]}
              labelFormatter={(label) => formatMonth(String(label), locale)}
            />
            <Legend wrapperStyle={{ fontSize: 10, paddingTop: 4 }} iconSize={8} />
            <Bar dataKey="income" name={incomeLabel} fill="var(--chart-2)" radius={[3, 3, 0, 0]} />
            <Bar dataKey="expense" name={spendingLabel} fill="var(--chart-4)" radius={[3, 3, 0, 0]} />
          </BarChart>
        </ResponsiveContainer>
      </CardContent>
    </Card>
  )
}
