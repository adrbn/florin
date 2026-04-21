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
  /** e.g. "/day avg" */
  dailyAvgLabel?: string
  /** e.g. "/day for {n} days" */
  dailyRemainingLabel?: (days: number) => string
}

/**
 * Dashboard + Reflect KPI showing how much of this month's salary is still
 * unspent. Goes red when negative (overspent); shows a helpful "no salary
 * detected" hint when the user hasn't been paid in the 90-day lookback.
 */
export function LeftToSpendCard({
  title,
  monthIncome,
  monthSpent,
  leftToSpend,
  dailyAvgSpent,
  dailyBudgetRemaining,
  daysRemaining,
  hintCategory,
  hintNoIncome,
  dailyAvgLabel = '/day avg',
  dailyRemainingLabel = (n) => `/day · ${n} days left`,
}: LeftToSpendCardProps) {
  const hasIncome = monthIncome > 0
  const tone = !hasIncome ? 'default' : leftToSpend < 0 ? 'negative' : 'positive'

  const dailyLine = hasIncome ? (
    <div className="tabular-nums">
      {formatCurrency(dailyAvgSpent)} {dailyAvgLabel}
      {dailyBudgetRemaining !== null && daysRemaining > 0 ? (
        <>
          {' · '}
          {formatCurrency(Math.max(0, dailyBudgetRemaining))}{' '}
          {dailyRemainingLabel(daysRemaining)}
        </>
      ) : null}
    </div>
  ) : null

  const hint = hasIncome ? (
    <div className="space-y-0.5">
      {hintCategory ? <div>{hintCategory}</div> : null}
      <div className="tabular-nums">
        {formatCurrency(monthIncome)} − {formatCurrency(monthSpent)}
      </div>
      {dailyLine}
    </div>
  ) : (
    <div>{hintNoIncome ?? 'No salary detected in the last 90 days.'}</div>
  )

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
