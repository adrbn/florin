'use client'

import { Cell, Pie, PieChart, ResponsiveContainer, Tooltip } from 'recharts'
import { Card, CardContent, CardHeader, CardTitle } from '../ui/card'
import { CATEGORICAL_PALETTE } from '../../lib/chart/palette'
import { formatCurrency } from '../../lib/format/currency'

interface CategoryShare {
  groupName: string
  categoryName: string
  emoji: string | null
  total: number
}

interface Props {
  data: ReadonlyArray<CategoryShare>
  /** Window label rendered in the title — purely cosmetic. */
  windowLabel: string
}

/**
 * Donut chart showing how spending is distributed across categories.
 * Bottom legend lists every slice with its share so the user can read
 * the chart even when the slices get small.
 */
export function CategoryBreakdownChart({ data, windowLabel }: Props) {
  const total = data.reduce((s, d) => s + d.total, 0)
  const top = [...data].sort((a, b) => b.total - a.total).slice(0, 10)
  const chartData = top.map((d, i) => ({
    name: `${d.emoji ? `${d.emoji} ` : ''}${d.categoryName}`,
    value: d.total,
    fill: CATEGORICAL_PALETTE[i % CATEGORICAL_PALETTE.length],
  }))

  return (
    <Card className="flex h-full flex-col">
      <CardHeader className="pb-1">
        <CardTitle className="text-xs uppercase tracking-wide text-muted-foreground">
          Spending breakdown — {windowLabel}
        </CardTitle>
      </CardHeader>
      <CardContent className="min-h-0 flex-1 pb-3">
        {chartData.length === 0 ? (
          <p className="py-6 text-center text-xs text-muted-foreground">
            No categorized spending in this window.
          </p>
        ) : (
          <div className="grid h-full min-h-0 grid-cols-1 gap-3 md:grid-cols-2">
            <div className="min-h-0">
              <ResponsiveContainer width="100%" height="100%" minHeight={140}>
                <PieChart>
                  <Pie
                    data={chartData}
                    dataKey="value"
                    nameKey="name"
                    innerRadius="55%"
                    outerRadius="85%"
                    paddingAngle={2}
                    isAnimationActive={false}
                  >
                    {chartData.map((entry) => (
                      <Cell key={entry.name} fill={entry.fill} />
                    ))}
                  </Pie>
                  <Tooltip
                    contentStyle={{
                      borderRadius: 8,
                      background: 'var(--popover)',
                      border: '1px solid var(--border)',
                      fontSize: 12,
                      color: 'var(--popover-foreground)',
                    }}
                    formatter={(value, name) => [formatCurrency(Number(value)), String(name)]}
                  />
                </PieChart>
              </ResponsiveContainer>
            </div>
            <ul className="min-h-0 space-y-1 overflow-y-auto pr-1 text-[11px]">
              {chartData.map((entry) => {
                const pct = total > 0 ? (entry.value / total) * 100 : 0
                return (
                  <li key={entry.name} className="flex items-center justify-between gap-2">
                    <span className="flex min-w-0 items-center gap-2">
                      <span
                        aria-hidden
                        className="h-2 w-2 flex-shrink-0 rounded-full"
                        style={{ backgroundColor: entry.fill }}
                      />
                      <span className="truncate text-foreground">{entry.name}</span>
                    </span>
                    <span className="flex items-center gap-2 whitespace-nowrap font-mono">
                      <span className="text-foreground">{formatCurrency(entry.value)}</span>
                      <span className="text-muted-foreground">{pct.toFixed(0)}%</span>
                    </span>
                  </li>
                )
              })}
            </ul>
          </div>
        )}
      </CardContent>
    </Card>
  )
}
