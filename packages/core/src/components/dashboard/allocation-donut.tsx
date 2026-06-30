'use client'

import { useMemo } from 'react'
import { Cell, Pie, PieChart, ResponsiveContainer, Tooltip } from 'recharts'
import { Card, CardContent, CardHeader, CardTitle } from '../ui/card'
import { NoSSR } from '../ui/no-ssr'
import { useT } from '../../i18n/context'
import { createCurrencyFormatter } from '../../lib/format/currency'
import { usePlayOnce } from '../../lib/use-play-once'
import type { NetWorthAllocation } from '../../types/index'

export interface AllocationDonutProps {
  allocation: NetWorthAllocation
  locale: string
}

/** Distinct hues for the three asset buckets — cash, invested, loans. */
const SEGMENT_COLORS = {
  cash: '#3b82f6',
  invested: '#10b981',
  loans: '#ef4444',
} as const

interface Segment {
  key: 'cash' | 'invested' | 'loans'
  label: string
  amount: number
  color: string
}

/**
 * Allocation donut for the dashboard — splits gross net worth into cash vs
 * invested, plus loans shown as a separate (red) liability slice. The donut is
 * drawn on positive magnitudes only (loans use their absolute remaining debt),
 * but the legend keeps loans labelled as a liability and shows the share of the
 * *gross* assets so the percentages read intuitively.
 *
 * Like {@link CategoryPie} it receives the locale as a prop and builds its own
 * currency formatter so it stays renderable from both web and desktop without
 * importing server code.
 */
export function AllocationDonut({ allocation, locale }: AllocationDonutProps) {
  const t = useT()
  const shouldAnimate = usePlayOnce('dashboard:allocationDonut')
  const fmt = useMemo(() => createCurrencyFormatter(locale, 'EUR'), [locale])

  const cashLabel = t('alloc.cash', 'Cash')
  const investedLabel = t('alloc.invested', 'Invested')
  const loansLabel = t('alloc.loans', 'Loans')

  const cash = Math.max(0, allocation.cash)
  const invested = Math.max(0, allocation.invested)
  const loans = Math.max(0, allocation.loans)

  const segments: Segment[] = useMemo(() => {
    const all: Segment[] = [
      { key: 'cash', label: cashLabel, amount: cash, color: SEGMENT_COLORS.cash },
      { key: 'invested', label: investedLabel, amount: invested, color: SEGMENT_COLORS.invested },
      { key: 'loans', label: loansLabel, amount: loans, color: SEGMENT_COLORS.loans },
    ]
    return all.filter((s) => s.amount > 0)
  }, [cash, invested, loans, cashLabel, investedLabel, loansLabel])

  const total = segments.reduce((sum, s) => sum + s.amount, 0)
  const grossAssets = cash + invested
  const net = grossAssets - loans

  return (
    <Card className="flex h-full flex-col">
      <CardHeader className="pb-2">
        <CardTitle className="text-sm font-medium">
          {t('alloc.title', 'Répartition du patrimoine')}
        </CardTitle>
        <p className="mt-0.5 text-[11px] text-muted-foreground">
          {total > 0
            ? t('alloc.netSubtitle', { amount: fmt.format(net) }, `Net: ${fmt.format(net)}`)
            : t('alloc.empty', 'No assets yet')}
        </p>
      </CardHeader>
      <CardContent className="flex min-h-0 flex-1 flex-col gap-3 pb-3">
        {total === 0 ? (
          <p className="text-xs text-muted-foreground">
            {t('alloc.empty', 'No assets yet')}
          </p>
        ) : (
          <>
            <div className="min-h-0 flex-1">
              <NoSSR fallback={<div className="h-full w-full" />}>
                <ResponsiveContainer width="100%" height="100%">
                  <PieChart>
                    <Pie
                      data={segments}
                      dataKey="amount"
                      nameKey="label"
                      cx="50%"
                      cy="50%"
                      outerRadius="80%"
                      innerRadius="58%"
                      paddingAngle={1.5}
                      stroke="var(--card)"
                      strokeWidth={1.5}
                      isAnimationActive={shouldAnimate}
                      animationDuration={900}
                      animationEasing="ease-out"
                    >
                      {segments.map((s) => (
                        <Cell key={s.key} fill={s.color} />
                      ))}
                    </Pie>
                    <Tooltip
                      cursor={false}
                      formatter={(value, name) => [fmt.format(Number(value)), String(name)]}
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
            </div>
            <ul className="space-y-1 text-[11px] tabular-nums">
              {segments.map((s) => {
                const pct = total > 0 ? (s.amount / total) * 100 : 0
                return (
                  <li key={s.key} className="flex items-center justify-between gap-2">
                    <span className="flex min-w-0 items-center gap-1.5">
                      <span
                        className="inline-block h-2 w-2 shrink-0 rounded-full"
                        style={{ backgroundColor: s.color }}
                        aria-hidden="true"
                      />
                      <span className="truncate text-muted-foreground">{s.label}</span>
                    </span>
                    <span className="shrink-0 font-medium">
                      {fmt.format(s.amount)}
                      <span className="ml-1 text-muted-foreground">{pct.toFixed(0)}%</span>
                    </span>
                  </li>
                )
              })}
            </ul>
          </>
        )}
      </CardContent>
    </Card>
  )
}
