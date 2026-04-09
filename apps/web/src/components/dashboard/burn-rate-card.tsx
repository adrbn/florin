import { Flame } from 'lucide-react'
import { formatCurrency } from '@/lib/format/currency'
import { getAvgMonthlyBurn, getMonthBurn } from '@/server/queries/dashboard'
import { KpiCard } from './kpi-card'

/** ISO date (YYYY-MM-DD) in local time — used for the `from`/`to` query
 *  params so the transactions filter matches the same month window the
 *  query uses. */
function isoLocal(d: Date): string {
  const y = d.getFullYear()
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${y}-${m}-${day}`
}

/**
 * Burn is always rendered in the "warning" (orange) tone by explicit user
 * request — it reads as a budget caution signal at a glance rather than
 * trying to dynamically reflect whether this month is tracking above or
 * below the 6-month average.
 *
 * The whole card is clickable: tapping it drops the user on the
 * Transactions page scoped to this month's window (no direction filter)
 * so they can see every row that influenced the KPI — negative spend AND
 * positive refunds on expense categories, which now net against the burn.
 * Filtering to direction=expense here would hide the refunds and make the
 * linked list disagree with the headline number.
 */
export async function BurnRateCard() {
  const [thisMonth, avg] = await Promise.all([getMonthBurn(), getAvgMonthlyBurn(6)])
  const now = new Date()
  const from = isoLocal(new Date(now.getFullYear(), now.getMonth(), 1))
  const to = isoLocal(new Date(now.getFullYear(), now.getMonth() + 1, 0))
  return (
    <KpiCard
      title="Burn this month"
      value={formatCurrency(thisMonth)}
      hint={`6-mo avg: ${formatCurrency(avg)}`}
      icon={Flame}
      tone="warning"
      href={{
        pathname: '/transactions',
        query: { from, to, excludeTransfers: '1' },
      }}
    />
  )
}
