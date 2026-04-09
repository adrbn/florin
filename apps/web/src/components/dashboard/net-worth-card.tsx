import { Wallet } from 'lucide-react'
import { formatCurrency } from '@/lib/format/currency'
import { getNetWorth } from '@/server/queries/dashboard'
import { KpiCard } from './kpi-card'

export async function NetWorthCard() {
  const { gross, liability, net } = await getNetWorth()
  // Show the gross ± debt breakdown so the user can eyeball where the
  // headline number comes from (gross = assets, debt = amortization
  // restant dû). When there's no loan configured, fall back to just gross.
  // Rendered as two separate stacked lines (rather than one concatenated
  // string) so the breakdown reads clearly on small cards and the numbers
  // line up vertically.
  const hint =
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
