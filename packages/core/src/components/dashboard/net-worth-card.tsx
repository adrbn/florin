import { Wallet } from 'lucide-react'
import type { ReactNode } from 'react'
import { formatCurrency } from '../../lib/format/currency'
import { KpiCard } from './kpi-card'

interface NetWorthCardProps {
  gross: number
  liability: number
  net: number
  title?: string
  grossLabel?: string
  debtLabel?: string
}

export function NetWorthCard({
  gross,
  liability,
  net,
  title = 'Net worth',
  grossLabel = 'Gross',
  debtLabel = '− Debt',
}: NetWorthCardProps) {
  const hint: ReactNode =
    liability > 0 ? (
      <span className="flex flex-col leading-tight tabular-nums">
        <span>
          {grossLabel} {formatCurrency(gross)}
        </span>
        <span>
          {debtLabel} {formatCurrency(liability)}
        </span>
      </span>
    ) : (
      `${grossLabel} ${formatCurrency(gross)}`
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
