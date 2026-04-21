import { Wallet } from 'lucide-react'
import { formatCurrency } from '../../lib/format/currency'
import { KpiCard } from './kpi-card'

interface LeftToSpendCardProps {
  title: string
  /** Income received this month for the detected salary category. */
  monthIncome: number
  /** Non-income burn already spent this month. */
  monthSpent: number
  /** monthIncome - monthSpent. Negative when overspent. */
  leftToSpend: number
  /** Average daily spend so far this month. */
  dailyAvgSpent: number
  /** leftToSpend / daysRemaining. Null when no salary or month is over. */
  dailyBudgetRemaining: number | null
  daysRemaining: number
  /** Hint fragments prebuilt by the caller so translations stay in the page. */
  hintCategory?: string
  hintNoIncome?: string
  /** e.g. "/day avg" (unused since v1.0.1 — kept for back-compat). */
  dailyAvgLabel?: string
  /** e.g. "/day for {n} days" (unused since v1.0.1 — kept for back-compat). */
  dailyRemainingLabel?: (days: number) => string
  /** Short label shown next to the daily budget, e.g. "/day". */
  perDayLabel?: string
}

/**
 * Dashboard + Reflect KPI showing how much of this month's salary is still
 * unspent. Goes red when negative (overspent); shows a helpful "no salary
 * detected" hint when the user hasn't been paid in the 90-day lookback.
 */
export function LeftToSpendCard({
  title,
  monthIncome,
  leftToSpend,
  dailyBudgetRemaining,
  daysRemaining,
  hintNoIncome,
  perDayLabel = '/day',
}: LeftToSpendCardProps) {
  const hasIncome = monthIncome > 0
  const tone = !hasIncome ? 'default' : leftToSpend < 0 ? 'negative' : 'positive'

  const hint =
    hasIncome && dailyBudgetRemaining !== null && daysRemaining > 0 ? (
      <div className="tabular-nums">
        {formatCurrency(Math.max(0, dailyBudgetRemaining))} {perDayLabel}
      </div>
    ) : !hasIncome ? (
      <div>{hintNoIncome ?? 'No salary detected in the last 90 days.'}</div>
    ) : null

  return (
    <KpiCard
      title={title}
      value={formatCurrency(hasIncome ? leftToSpend : 0)}
      hint={hint}
      icon={Wallet}
      tone={tone}
    />
  )
}
