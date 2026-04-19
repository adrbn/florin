import type { MonthPlan } from '@florin/core/types'
import { formatCurrency } from '@florin/core/lib/format'

interface PlanBannerProps {
  plan: MonthPlan
  currency: string
}

export function PlanBanner({ plan, currency }: PlanBannerProps) {
  const overAssigned = plan.readyToAssign < 0
  const banner = overAssigned
    ? {
        text: `${formatCurrency(plan.readyToAssign)} Assigned Too Much`,
        className: 'bg-red-500 text-red-50',
      }
    : plan.readyToAssign > 0
      ? {
          text: `${formatCurrency(plan.readyToAssign)} Ready to Assign`,
          className: 'bg-emerald-500 text-emerald-50',
        }
      : {
          text: 'All assigned',
          className: 'bg-muted text-muted-foreground',
        }

  return (
    <div className="px-4 py-3 border-b border-border flex items-center gap-3">
      <div
        className={`flex-1 rounded-full px-4 py-2 text-sm font-semibold flex items-center justify-between ${banner.className}`}
        data-testid="plan-banner"
      >
        <span>{banner.text}</span>
        <span className="text-xs font-normal opacity-80">
          Income {formatCurrency(plan.income)} · Assigned {formatCurrency(plan.totalAssigned)}
        </span>
      </div>
      {plan.overspentCount > 0 ? (
        <span className="inline-flex items-center rounded-full bg-red-500/15 text-red-500 border border-red-500/30 px-3 py-1 text-xs font-medium shrink-0">
          {plan.overspentCount} overspent
        </span>
      ) : null}
    </div>
  )
}
