import { Flame } from 'lucide-react'
import { formatCurrency } from '../../lib/format/currency'
import { KpiCard } from './kpi-card'

interface BurnRateCardProps {
  thisMonth: number
  avg: number
  href: {
    pathname: string
    query: Record<string, string>
  }
}

export function BurnRateCard({ thisMonth, avg, href }: BurnRateCardProps) {
  return (
    <KpiCard
      title="Burn this month"
      value={formatCurrency(thisMonth)}
      hint={`6-mo avg: ${formatCurrency(avg)}`}
      icon={Flame}
      tone="warning"
      href={href}
    />
  )
}
