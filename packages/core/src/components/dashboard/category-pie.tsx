'use client'

import { Cell, Pie, PieChart, ResponsiveContainer, Tooltip } from 'recharts'
import { Card, CardContent, CardHeader, CardTitle } from '../ui/card'
import { NoSSR } from '../ui/no-ssr'
import { CATEGORICAL_PALETTE } from '../../lib/chart/palette'
import { formatCurrency } from '../../lib/format/currency'

export interface CategoryDatum {
  categoryName: string
  emoji: string | null
  total: number
  color: string | null
}

export interface CategoryPieProps {
  data: CategoryDatum[]
  uncategorizedCount: number
  title?: string
}

export function CategoryPie({ data, uncategorizedCount, title = 'This month by category' }: CategoryPieProps) {
  const emptyMessage =
    uncategorizedCount > 0
      ? `${uncategorizedCount} expense${uncategorizedCount === 1 ? '' : 's'} this month — all uncategorized. Categorize them in Transactions to see the breakdown.`
      : 'No expense yet this month.'
  const total = data.reduce((sum, d) => sum + d.total, 0)
  return (
    <Card className="flex h-full flex-col">
      <CardHeader className="pb-2">
        <CardTitle className="text-sm font-medium">{title}</CardTitle>
        <p className="mt-0.5 text-[11px] text-muted-foreground">
          {total > 0 ? `${formatCurrency(total)} across ${data.length} categories` : 'Breakdown'}
        </p>
      </CardHeader>
      <CardContent className="min-h-0 flex-1 pb-3">
        {data.length === 0 ? (
          <p className="text-xs text-muted-foreground">{emptyMessage}</p>
        ) : (
          <NoSSR fallback={<div className="h-full w-full" />}>
            <ResponsiveContainer width="100%" height="100%">
              <PieChart>
                <Pie
                  data={data}
                  dataKey="total"
                  nameKey="categoryName"
                  cx="50%"
                  cy="50%"
                  outerRadius="78%"
                  innerRadius="55%"
                  paddingAngle={1.5}
                  stroke="var(--card)"
                  strokeWidth={1.5}
                  isAnimationActive={false}
                >
                  {data.map((d, i) => (
                    <Cell
                      key={d.categoryName}
                      fill={CATEGORICAL_PALETTE[i % CATEGORICAL_PALETTE.length]}
                    />
                  ))}
                </Pie>
                <Tooltip
                  cursor={false}
                  formatter={(value, name) => [formatCurrency(Number(value)), String(name)]}
                  contentStyle={{
                    borderRadius: 10,
                    background: 'var(--popover)',
                    border: '1px solid var(--border)',
                    color: 'var(--popover-foreground)',
                    fontSize: 12,
                    padding: '8px 10px',
                    boxShadow: '0 6px 24px -12px rgb(0 0 0 / 0.25)',
                  }}
                  itemStyle={{ color: 'var(--popover-foreground)' }}
                />
              </PieChart>
            </ResponsiveContainer>
          </NoSSR>
        )}
      </CardContent>
    </Card>
  )
}
