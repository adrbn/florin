import { Wallet } from 'lucide-react'
import { formatCurrency } from '@/lib/format/currency'
import { getNetWorth } from '@/server/queries/dashboard'
import { KpiCard } from './kpi-card'

export async function NetWorthCard() {
  const { gross, liability, net } = await getNetWorth()
  // Show the gross ± debt breakdown so the user can eyeball where the
  // headline number comes from (gross = assets, debt = amortization
  // restant dû). When there's no loan configured, fall back to just gross.
  const hint =
    liability > 0
      ? `Gross ${formatCurrency(gross)} − Debt ${formatCurrency(liability)}`
      : `Gross: ${formatCurrency(gross)}`
  return (
    <KpiCard
      title="Net worth"
      value={formatCurrency(net)}
      hint={hint}
      icon={Wallet}
      tone={net >= 0 ? 'positive' : 'negative'}
    />
  )
}
