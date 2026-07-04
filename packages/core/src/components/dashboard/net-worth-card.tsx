import { Wallet } from 'lucide-react'
import type { ReactNode } from 'react'
import { formatCurrency } from '../../lib/format/currency'
import { KpiCard } from './kpi-card'

interface NetWorthCardProps {
  gross: number
  liability: number
  net: number
  /**
   * Average monthly change of net worth (OLS trend, same as the patrimony
   * chart). This is what belongs under a net-worth figure — how it's growing —
   * rather than a timing-sensitive "this month" savings number. Null hides it.
   */
  monthlyTrend?: number | null
  title?: string
  grossLabel?: string
  debtLabel?: string
  monthlyTrendLabel?: string
}

export function NetWorthCard({
  gross,
  net,
  monthlyTrend,
  title = 'Net worth',
  grossLabel = 'Gross',
  monthlyTrendLabel = '/mo trend',
}: NetWorthCardProps) {
  const deltaLine =
    monthlyTrend !== null && monthlyTrend !== undefined
      ? renderDelta(monthlyTrend, monthlyTrendLabel)
      : null

  const hint: ReactNode = (
    <span className="flex flex-col leading-tight tabular-nums">
      <span>
        {grossLabel} {formatCurrency(gross)}
      </span>
      {deltaLine}
    </span>
  )

  return (
    <KpiCard
      title={title}
      value={formatCurrency(net)}
      hint={hint}
      icon={Wallet}
      tone={net >= 0 ? 'positive' : 'negative'}
      href="/reflect"
    />
  )
}

function renderDelta(delta: number, label: string): ReactNode {
  const sign = delta >= 0 ? '+' : '−'
  const toneClass =
    delta > 0
      ? 'text-emerald-600 dark:text-emerald-400'
      : delta < 0
        ? 'text-destructive'
        : 'text-muted-foreground'
  return (
    <span className={toneClass}>
      {sign}
      {formatCurrency(Math.abs(delta))} {label}
    </span>
  )
}
