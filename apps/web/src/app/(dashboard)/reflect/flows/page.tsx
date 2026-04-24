import { IncomeVsSpendingChart } from '@florin/core/components/reflect/income-vs-spending-chart'
import { NetWorthChart } from '@florin/core/components/reflect/net-worth-chart'
import { SavingsRateRolling } from '@florin/core/components/reflect/savings-rate-rolling'
import { LeftToSpendCard } from '@florin/core/components/dashboard/left-to-spend-card'
import { queries } from '@/db/client'
import { getServerT } from '@/lib/locale'

// Money-in vs money-out deep dive. Focused on rates/flows rather than
// categories — the "are we saving or burning?" view.
export const dynamic = 'force-dynamic'

export default async function ReflectFlowsPage() {
  const t = await getServerT()
  const [flows, netWorthSeries, savingsRates, leftToSpend] = await Promise.all([
    queries.getMonthlyFlows(24),
    queries.getNetWorthSeries(24),
    queries.getSavingsRates(),
    queries.getLeftToSpendThisMonth(),
  ])

  return (
    <div className="flex min-h-0 flex-col gap-3">
      <header className="min-w-0">
        <h1 className="text-xl font-semibold tracking-tight sm:text-2xl">
          {t('reflect.flows.title', 'Income vs spending')}
        </h1>
        <p className="mt-0.5 text-xs text-muted-foreground">
          {t(
            'reflect.flows.subtitle',
            'Monthly flows, net worth trajectory, and rolling savings rate — the shape of your year.',
          )}
        </p>
      </header>

      <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
        <LeftToSpendCard
          title={t('kpi.leftToSpend', 'Left to spend')}
          monthIncome={leftToSpend.monthIncome}
          monthSpent={leftToSpend.monthSpent}
          leftToSpend={leftToSpend.leftToSpend}
          dailyAvgSpent={leftToSpend.dailyAvgSpent}
          dailyBudgetRemaining={leftToSpend.dailyBudgetRemaining}
          daysRemaining={leftToSpend.daysRemaining}
          hintCategory={
            leftToSpend.salaryCategoryName
              ? t(
                  'kpi.leftToSpendCategory',
                  { category: leftToSpend.salaryCategoryName },
                  'Based on “{category}”',
                )
              : undefined
          }
          hintNoIncome={t('kpi.leftToSpendNoIncome', 'No salary detected in the last 90 days.')}
          perDayLabel={t('kpi.perDay', '/day')}
        />
        <SavingsRateRolling
          rates={savingsRates}
          title={t('reflect.savingsRolling', 'Savings rate — rolling')}
          subtitle={t('reflect.savingsRollingSubtitle', 'Saved ÷ income over 3, 6, 12 months.')}
          labels={{
            threeMonth: t('reflect.threeMonth', '3 mo'),
            sixMonth: t('reflect.sixMonth', '6 mo'),
            twelveMonth: t('reflect.twelveMonth', '12 mo'),
            noData: t('reflect.noIncome', 'no income'),
          }}
        />
      </div>

      <div className="min-h-[320px]">
        <IncomeVsSpendingChart
          data={flows}
          title={t('reflect.incomeVsSpending', 'Income vs spending')}
          incomeLabel={t('transactions.directionIncome', 'Income')}
          spendingLabel={t('transactions.directionExpenses', 'Spending')}
        />
      </div>

      <div className="min-h-[320px]">
        <NetWorthChart
          data={netWorthSeries}
          title={t('reflect.netWorth', 'Net worth')}
          netWorthTooltipLabel={t('reflect.netWorth', 'Net worth')}
        />
      </div>
    </div>
  )
}
