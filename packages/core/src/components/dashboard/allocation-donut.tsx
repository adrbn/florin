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

const CASH_COLOR = '#3b82f6'
const INVESTED_COLOR = '#10b981'
const LOAN_COLOR = '#ef4444'

/**
 * Asset-allocation card. The donut shows ASSETS only — cash vs invested — with
 * the share invested called out big in the center, so the card answers one
 * question at a glance: "how much of my money is actually invested?". Loans are
 * a liability, not an asset, so they're shown as a separate line below the
 * legend rather than muddying the pie. Receives the locale as a prop and builds
 * its own currency formatter so it renders from both web and desktop.
 */
export function AllocationDonut({ allocation, locale }: AllocationDonutProps) {
  const t = useT()
  const shouldAnimate = usePlayOnce('dashboard:allocationDonut')
  const fmt = useMemo(() => createCurrencyFormatter(locale, 'EUR'), [locale])

  const cashLabel = t('alloc.cash', 'Liquidités')
  const investedLabel = t('alloc.invested', 'Investi')
  const loansLabel = t('alloc.loans', 'Emprunts')

  const cash = Math.max(0, allocation.cash)
  const invested = Math.max(0, allocation.invested)
  const loans = Math.max(0, allocation.loans)
  const assets = cash + invested
  const net = assets - loans
  const investedPct = assets > 0 ? (invested / assets) * 100 : 0

  const segments = useMemo(() => {
    const all = [
      { key: 'invested', label: investedLabel, amount: invested, color: INVESTED_COLOR },
      { key: 'cash', label: cashLabel, amount: cash, color: CASH_COLOR },
    ]
    return all.filter((s) => s.amount > 0)
  }, [cash, invested, cashLabel, investedLabel])

  return (
    <Card className="flex h-full flex-col">
      <CardHeader className="pb-2">
        <CardTitle className="text-sm font-medium">
          {t('alloc.title', 'Répartition du patrimoine')}
        </CardTitle>
        <p className="mt-0.5 text-[11px] text-muted-foreground">
          {assets > 0
            ? t('alloc.netSubtitle', { amount: fmt.format(net) }, `Net: ${fmt.format(net)}`)
            : t('alloc.empty', 'Aucun actif')}
        </p>
      </CardHeader>
      <CardContent className="flex min-h-0 flex-1 flex-col pb-3">
        {assets === 0 ? (
          <p className="text-xs text-muted-foreground">{t('alloc.empty', 'Aucun actif')}</p>
        ) : (
          <div className="flex min-h-0 flex-1 items-center gap-2">
            {/* Donut with the share invested in the center. */}
            <div className="relative h-full min-h-[130px] w-[38%] shrink-0">
              <NoSSR fallback={<div className="h-full w-full" />}>
                <ResponsiveContainer width="100%" height="100%">
                  <PieChart>
                    <Pie
                      data={segments}
                      dataKey="amount"
                      nameKey="label"
                      cx="50%"
                      cy="50%"
                      outerRadius="94%"
                      innerRadius="68%"
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
              <div className="pointer-events-none absolute inset-0 flex flex-col items-center justify-center">
                <span className="text-2xl font-bold leading-none">{investedPct.toFixed(0)}%</span>
                <span className="mt-1 text-[10px] uppercase tracking-wide text-muted-foreground">
                  {t('alloc.investedShareLabel', 'investi')}
                </span>
              </div>
            </div>

            {/* Legend — invested first (the number that matters), then cash, then loans. */}
            <ul className="flex min-w-0 flex-1 flex-col justify-center gap-1.5 text-[11px] tabular-nums">
              <li className="flex items-center justify-between gap-2">
                <span className="flex min-w-0 items-center gap-1.5">
                  <span
                    className="inline-block h-2.5 w-2.5 shrink-0 rounded-full"
                    style={{ backgroundColor: INVESTED_COLOR }}
                    aria-hidden="true"
                  />
                  <span className="truncate text-muted-foreground">{investedLabel}</span>
                </span>
                <span className="shrink-0 font-semibold">{fmt.format(invested)}</span>
              </li>
              <li className="flex items-center justify-between gap-2">
                <span className="flex min-w-0 items-center gap-1.5">
                  <span
                    className="inline-block h-2.5 w-2.5 shrink-0 rounded-full"
                    style={{ backgroundColor: CASH_COLOR }}
                    aria-hidden="true"
                  />
                  <span className="truncate text-muted-foreground">{cashLabel}</span>
                </span>
                <span className="shrink-0 font-medium">{fmt.format(cash)}</span>
              </li>
              {loans > 0 && (
                <li className="mt-1 flex items-center justify-between gap-2 border-t border-border/40 pt-2.5">
                  <span className="flex min-w-0 items-center gap-1.5">
                    <span
                      className="inline-block h-2.5 w-2.5 shrink-0 rounded-full"
                      style={{ backgroundColor: LOAN_COLOR }}
                      aria-hidden="true"
                    />
                    <span className="truncate text-muted-foreground">{loansLabel}</span>
                  </span>
                  <span className="shrink-0 font-medium text-destructive">
                    −{fmt.format(loans)}
                  </span>
                </li>
              )}
            </ul>
          </div>
        )}
      </CardContent>
    </Card>
  )
}
