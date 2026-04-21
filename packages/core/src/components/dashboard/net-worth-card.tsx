import { Wallet } from 'lucide-react'
import type { ReactNode } from 'react'
import { formatCurrency } from '../../lib/format/currency'
import { KpiCard } from './kpi-card'

interface NetWorthCardProps {
  gross: number
  liability: number
  net: number
  netMonthAgo?: number | null
  title?: string
  grossLabel?: string
  debtLabel?: string
  vsLastMonthLabel?: string
}

export function NetWorthCard({
  gross,
  liability,
  net,
  netMonthAgo,
  title = 'Net worth',
  grossLabel = 'Gross',
  debtLabel = '− Debt',
  vsLastMonthLabel = 'vs last month',
}: NetWorthCardProps) {
  const delta =
    netMonthAgo !== null && netMonthAgo !== undefined ? net - netMonthAgo : null
  const deltaLine = delta !== null ? renderDelta(delta, vsLastMonthLabel) : null

  const hint: ReactNode = (
    <span className="flex flex-col leading-tight tabular-nums">
      {liability > 0 ? (
        <>
          <span>
            {grossLabel} {formatCurrency(gross)}
          </span>
          <span>
            {debtLabel} {formatCurrency(liability)}
          </span>
        </>
      ) : (
        <span>
          {grossLabel} {formatCurrency(gross)}
        </span>
      )}
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
