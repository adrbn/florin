'use client'

import {
  Area,
  AreaChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'

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

export function NetWorthChart({ data }: { data: ReadonlyArray<NetWorthPoint> }) {
  return (
    <Card className="flex h-full flex-col">
      <CardHeader className="pb-2">
        <CardTitle className="text-base">Net worth — last 24 months</CardTitle>
      </CardHeader>
      <CardContent className="min-h-0 flex-1 pb-3">
        <ResponsiveContainer width="100%" height={280}>
          <AreaChart data={[...data]} margin={{ top: 10, right: 16, left: 0, bottom: 0 }}>
            <defs>
              <linearGradient id="nwGrad" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor="#3b82f6" stopOpacity={0.45} />
                <stop offset="100%" stopColor="#3b82f6" stopOpacity={0} />
              </linearGradient>
            </defs>
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
              formatter={(value) => [formatEur(Number(value)), 'Cumulative']}
              labelFormatter={(label) => formatMonth(String(label))}
            />
            <Area
              type="monotone"
              dataKey="cumulative"
              stroke="#3b82f6"
              strokeWidth={2}
              fill="url(#nwGrad)"
              isAnimationActive={false}
            />
          </AreaChart>
        </ResponsiveContainer>
      </CardContent>
    </Card>
  )
}
