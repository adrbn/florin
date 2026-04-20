import { CategoryBreakdownChart } from '@florin/core/components/reflect/category-breakdown-chart'
import { CounterfactualCard } from '@florin/core/components/reflect/counterfactual-card'
import { IncomeVsSpendingChart } from '@florin/core/components/reflect/income-vs-spending-chart'
import { NetWorthChart } from '@florin/core/components/reflect/net-worth-chart'
import { SavingsRateRolling } from '@florin/core/components/reflect/savings-rate-rolling'
import { SubscriptionsList } from '@florin/core/components/reflect/subscriptions-list'
import { WeeklyHeatmap } from '@florin/core/components/reflect/weekly-heatmap'
import { LeftToSpendCard } from '@florin/core/components/dashboard/left-to-spend-card'
import { Card, CardContent, CardHeader, CardTitle } from '@florin/core/components/ui/card'
import { formatCurrency } from '@florin/core/lib/format'
import { queries } from '@/db/client'
import { getServerT } from '@/lib/locale'
import { PdfExportButton } from '@/components/pdf-export-button'

// Reflect reads from the database on every render — never prerender it at
// build time, otherwise the user would see frozen numbers from the moment
// the image was built.
export const dynamic = 'force-dynamic'

const HEATMAP_WEEKS = 52
const HEATMAP_WINDOW_DAYS = HEATMAP_WEEKS * 7 + 7
const COUNTERFACTUAL_WINDOW_DAYS = 90

export default async function ReflectPage() {
  const t = await getServerT()
  const [
    flows,
    categoryShare,
    ageOfMoney,
    netWorthSeries,
    netWorth,
    leftToSpend,
    dailyByCategory,
    savingsRates,
    subscriptions,
  ] = await Promise.all([
    queries.getMonthlyFlows(12),
    queries.getCategoryBreakdown(COUNTERFACTUAL_WINDOW_DAYS),
    queries.getAgeOfMoney(90),
    queries.getNetWorthSeries(24),
    queries.getNetWorth(),
    queries.getLeftToSpendThisMonth(),
    queries.getDailySpendByCategory(HEATMAP_WINDOW_DAYS),
    queries.getSavingsRates(),
    queries.getSubscriptions(),
  ])

  const last12 = flows.reduce(
    (acc, f) => ({
      income: acc.income + f.income,
      expense: acc.expense + f.expense,
    }),
    { income: 0, expense: 0 },
  )
  const savingsRate =
    last12.income > 0 ? ((last12.income - last12.expense) / last12.income) * 100 : 0

  return (
    <div className="flex min-h-0 flex-col gap-3">
      <header className="flex items-start justify-between gap-4">
        <div className="min-w-0">
          <h1 className="text-xl font-semibold tracking-tight sm:text-2xl">
            {t('reflect.title', 'Reflect')}
          </h1>
          <p className="mt-0.5 text-xs text-muted-foreground">
            {t('reflect.subtitle', 'Long-window analytics — how your money has actually moved.')}
          </p>
        </div>
        <PdfExportButton />
      </header>

      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <Card className="gap-1 py-3">
          <CardHeader className="px-4 py-0">
            <CardTitle className="text-[10px] uppercase tracking-wide text-muted-foreground">
              {t('reflect.netWorth', 'Net worth')}
            </CardTitle>
          </CardHeader>
          <CardContent className="px-4 py-0">
            <p className="text-xl font-bold tabular-nums">{formatCurrency(netWorth.net)}</p>
            <p className="mt-0.5 text-[10px] text-muted-foreground">
              {t('kpi.grossPrefix', 'Gross')} {formatCurrency(netWorth.gross)}
            </p>
          </CardContent>
        </Card>
        <Card className="gap-1 py-3">
          <CardHeader className="px-4 py-0">
            <CardTitle className="text-[10px] uppercase tracking-wide text-muted-foreground">
              {t('reflect.income12mo', 'Income (12mo)')}
            </CardTitle>
          </CardHeader>
          <CardContent className="px-4 py-0">
            <p className="text-xl font-bold tabular-nums text-emerald-600 dark:text-emerald-400">
              {formatCurrency(last12.income)}
            </p>
          </CardContent>
        </Card>
        <Card className="gap-1 py-3">
          <CardHeader className="px-4 py-0">
            <CardTitle className="text-[10px] uppercase tracking-wide text-muted-foreground">
              {t('reflect.spending12mo', 'Spending (12mo)')}
            </CardTitle>
          </CardHeader>
          <CardContent className="px-4 py-0">
            <p className="text-xl font-bold tabular-nums text-destructive">
              {formatCurrency(last12.expense)}
            </p>
          </CardContent>
        </Card>
        <Card className="gap-1 py-3">
          <CardHeader className="px-4 py-0">
            <CardTitle className="text-[10px] uppercase tracking-wide text-muted-foreground">
              {t('reflect.ageOfMoney', 'Age of money')}
            </CardTitle>
          </CardHeader>
          <CardContent className="px-4 py-0">
            <p className="text-xl font-bold tabular-nums">
              {ageOfMoney === null ? '—' : `${Math.round(ageOfMoney)} ${t('reflect.days', 'd')}`}
            </p>
            <p className="mt-0.5 text-[10px] text-muted-foreground">
              {t('reflect.savingsRateHint', '{pct} savings rate').replace(
                '{pct}',
                `${savingsRate >= 0 ? '+' : ''}${savingsRate.toFixed(0)}%`,
              )}
            </p>
          </CardContent>
        </Card>
      </div>

      <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
        <LeftToSpendCard
          title={t('kpi.leftToSpend', 'Monthly margin')}
          monthIncome={leftToSpend.monthIncome}
          monthSpent={leftToSpend.monthSpent}
          leftToSpend={leftToSpend.leftToSpend}
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

      <WeeklyHeatmap rows={dailyByCategory} weeks={HEATMAP_WEEKS} />

      <div className="grid grid-cols-1 gap-3 md:grid-cols-2">
        <SubscriptionsList
          rows={subscriptions}
          title={t('reflect.subscriptions', 'Subscriptions radar')}
          subtitle={t('reflect.subscriptionsSubtitle', 'Recurring charges detected in the last 6 months.')}
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

      <div className="grid min-h-0 grid-cols-1 gap-3 lg:grid-cols-12">
        <div className="min-h-[240px] lg:col-span-7 lg:min-h-0">
          <IncomeVsSpendingChart
            data={flows}
            title={t('reflect.incomeVsSpending', 'Income vs spending')}
            incomeLabel={t('transactions.directionIncome', 'Income')}
            spendingLabel={t('transactions.directionExpenses', 'Spending')}
          />
        </div>
        <div className="min-h-[240px] lg:col-span-5 lg:min-h-0">
          <NetWorthChart
            data={netWorthSeries}
            title={t('reflect.netWorth', 'Net worth')}
            netWorthTooltipLabel={t('reflect.netWorth', 'Net worth')}
          />
        </div>
        <div className="min-h-[240px] lg:col-span-12 lg:min-h-0">
          <CategoryBreakdownChart
            data={categoryShare}
            windowLabel={t('dashboard.lastNDays', 'Last {n} days').replace('{n}', '90')}
            titlePrefix={t('reflect.spendingBreakdown', 'Spending breakdown — last 90 days').split(' — ')[0] ?? 'Spending breakdown'}
          />
        </div>
      </div>
    </div>
  )
}
