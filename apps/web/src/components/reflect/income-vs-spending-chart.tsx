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
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'

interface MonthlyFlow {
  month: string
  income: number
  expense: number
  net: number
}

const formatEur = (v: number): string => `${Math.round(v).toLocaleString('fr-FR')} €`

const formatMonth = (m: string): string => {
  const [year, month] = m.split('-')
  if (!year || !month) return m
  const d = new Date(Number(year), Number(month) - 1, 1)
  return d.toLocaleDateString('fr-FR', { month: 'short' })
}

export function IncomeVsSpendingChart({ data }: { data: ReadonlyArray<MonthlyFlow> }) {
  return (
    <Card className="flex h-full flex-col">
      <CardHeader className="pb-2">
        <CardTitle className="text-base">Income vs spending</CardTitle>
      </CardHeader>
      <CardContent className="min-h-0 flex-1 pb-3">
        <ResponsiveContainer width="100%" height={280}>
          <BarChart data={[...data]} margin={{ top: 10, right: 16, left: 0, bottom: 0 }}>
            <CartesianGrid strokeDasharray="3 3" className="stroke-muted" />
            <XAxis dataKey="month" tickFormatter={formatMonth} className="text-xs" />
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
              labelFormatter={(label) => formatMonth(String(label))}
            />
            <Legend wrapperStyle={{ fontSize: 11 }} />
            <Bar dataKey="income" name="Income" fill="#10b981" radius={[3, 3, 0, 0]} />
            <Bar dataKey="expense" name="Spending" fill="#ef4444" radius={[3, 3, 0, 0]} />
          </BarChart>
        </ResponsiveContainer>
      </CardContent>
    </Card>
  )
}
