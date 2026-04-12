import { Wallet } from 'lucide-react'
import type { ReactNode } from 'react'
import { formatCurrency } from '../../lib/format/currency'
import { KpiCard } from './kpi-card'

interface NetWorthCardProps {
  gross: number
  liability: number
  net: number
}

export function NetWorthCard({ gross, liability, net }: NetWorthCardProps) {
  const hint: ReactNode =
    liability > 0 ? (
      <span className="flex flex-col leading-tight tabular-nums">
        <span>Gross {formatCurrency(gross)}</span>
        <span>− Debt {formatCurrency(liability)}</span>
      </span>
    ) : (
      `Gross ${formatCurrency(gross)}`
    )
  return (
    <KpiCard
      title="Net worth"
      value={formatCurrency(net)}
      hint={hint}
      icon={Wallet}
      tone={net >= 0 ? 'positive' : 'negative'}
      href="/reflect"
    />
  )
}
