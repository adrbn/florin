import { Wallet } from 'lucide-react'
import { formatCurrency } from '@/lib/format/currency'
import { getNetWorth } from '@/server/queries/dashboard'
import { KpiCard } from './kpi-card'

export async function NetWorthCard() {
  const { gross, net } = await getNetWorth()
  return (
    <KpiCard
      title="Net worth"
      value={formatCurrency(net)}
      hint={`Gross: ${formatCurrency(gross)}`}
      icon={Wallet}
      tone={net >= 0 ? 'positive' : 'negative'}
    />
  )
}
