import { CounterfactualCard } from '@florin/core/components/reflect/counterfactual-card'
import { SubscriptionsList } from '@florin/core/components/reflect/subscriptions-list'
import { queries } from '@/db/client'
import { getServerT } from '@/lib/locale'

const COUNTERFACTUAL_WINDOW_DAYS = 90

export const dynamic = 'force-dynamic'

export default async function ReflectSubscriptionsPage() {
  const t = await getServerT()
  const [subscriptions, categoryShare] = await Promise.all([
    queries.getSubscriptions(),
    queries.getCategoryBreakdown(COUNTERFACTUAL_WINDOW_DAYS),
  ])

  return (
    <div className="flex min-h-0 flex-col gap-3">
      <header className="min-w-0">
        <h1 className="text-xl font-semibold tracking-tight sm:text-2xl">
          {t('reflect.subs.title', 'Subscriptions & cuts')}
        </h1>
        <p className="mt-0.5 text-xs text-muted-foreground">
          {t(
            'reflect.subs.subtitle',
            'Recurring charges detected automatically, and a what-if calculator showing the annual impact of cutting a category.',
          )}
        </p>
      </header>

      <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
        <SubscriptionsList
          rows={subscriptions}
          title={t('reflect.subscriptions', 'Subscriptions radar')}
          subtitle={t(
            'reflect.subscriptionsSubtitle',
            'Recurring charges detected in the last 6 months.',
          )}
          empty={t('reflect.subscriptionsEmpty', 'No recurring charges detected yet.')}
          annualLabel={t('reflect.annualCostLabel', 'Annual cost of detected subscriptions')}
          cadenceMonthly={t('reflect.cadenceMonthly', 'monthly')}
          cadenceWeekly={t('reflect.cadenceWeekly', 'weekly')}
          cadenceOther={(n) => t('reflect.cadenceOther', { n }, 'every {n} days')}
        />
        <CounterfactualCard
          categories={categoryShare}
          windowDays={COUNTERFACTUAL_WINDOW_DAYS}
          title={t('reflect.counterfactual', 'If I stopped…')}
          subtitle={t(
            'reflect.counterfactualSubtitle',
            'Tick categories you could cut. Projected from the last 90 days.',
          )}
          suggestion={t('reflect.counterfactualSavings', 'You’d save')}
          yearLabel={t('reflect.year', 'year')}
          noDataLabel={t('reflect.noSpendingData', 'Not enough spending history yet.')}
        />
      </div>
    </div>
  )
}
