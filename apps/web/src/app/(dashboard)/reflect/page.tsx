import { CategoryBreakdownChart } from '@florin/core/components/reflect/category-breakdown-chart'
import { CategoryTrendsChart } from '@florin/core/components/reflect/category-trends-chart'
import { CounterfactualCard } from '@florin/core/components/reflect/counterfactual-card'
import { IncomeVsSpendingChart } from '@florin/core/components/reflect/income-vs-spending-chart'
import { NetWorthChart } from '@florin/core/components/reflect/net-worth-chart'
import { SavingsRateRolling } from '@florin/core/components/reflect/savings-rate-rolling'
import { SubscriptionsList } from '@florin/core/components/reflect/subscriptions-list'
import { WeeklyHeatmap } from '@florin/core/components/reflect/weekly-heatmap'
import { MonthForecastCard } from '@florin/core/components/reflect/month-forecast-card'
import { CategoryMoversCard } from '@florin/core/components/reflect/category-movers-card'
import { RecurringSplitCard } from '@florin/core/components/reflect/recurring-split-card'
import { SpendingAnomaliesCard } from '@florin/core/components/reflect/spending-anomalies-card'
import { LeftToSpendCard } from '@florin/core/components/dashboard/left-to-spend-card'
import { CategoryPie } from '@florin/core/components/dashboard/category-pie'
import { TopExpensesCard } from '@florin/core/components/dashboard/top-expenses-card'
import { KpiCard } from '@florin/core/components/dashboard/kpi-card'
import { Card, CardContent } from '@florin/core/components/ui/card'
import { Hourglass, LineChart, TrendingDown, TrendingUp, Wallet } from 'lucide-react'
import { formatCurrency } from '@florin/core/lib/format'
import { queries } from '@/db/client'
import { getServerT } from '@/lib/locale'
import { fetchTopSpend } from '@/server/actions/dashboard'

// Reflect reads from the database on every render — never prerender it at
// build time, otherwise the user would see frozen numbers from the moment
// the image was built.
export const dynamic = 'force-dynamic'

const HEATMAP_WEEKS = 52
const HEATMAP_WINDOW_DAYS = HEATMAP_WEEKS * 7 + 7 // pad so the oldest column is full
const COUNTERFACTUAL_WINDOW_DAYS = 90

export default async function ReflectPage() {
  const t = await getServerT()
  const [
    flows,
    categoryShare,
    categoryTrends,
    ageOfMoney,
    netWorthSeries,
    netWorth,
    leftToSpend,
    dailyByCategory,
    savingsRates,
    subscriptions,
    monthByCategory,
    uncategorizedCount,
    topSpendInitial,
    categoryList,
  ] = await Promise.all([
    queries.getMonthlyFlows(12),
    queries.getCategoryBreakdown(COUNTERFACTUAL_WINDOW_DAYS),
    queries.getCategorySpendingSeries(12),
    queries.getAgeOfMoney(90),
    queries.getNetWorthSeries(24),
    queries.getNetWorth(),
    queries.getLeftToSpendThisMonth(),
    queries.getDailySpendByCategory(HEATMAP_WINDOW_DAYS),
    queries.getSavingsRates(),
    queries.getSubscriptions(),
    queries.getMonthByCategory(),
    queries.countUncategorizedExpensesThisMonth(),
    queries.getTopSpend({ mode: 'transactions', limit: 5, days: 30, categoryId: null, minAmount: 0 }),
    queries.listCategoriesFlat(),
  ])

  const topSpendCategories = categoryList.map((c) => ({
    id: c.id,
    name: c.name,
    emoji: c.emoji,
    groupName: c.groupName,
  }))

  const last12 = flows.reduce(
    (acc, f) => ({
      income: acc.income + f.income,
      expense: acc.expense + f.expense,
    }),
    { income: 0, expense: 0 },
  )
  const savingsRate =
    last12.income > 0 ? ((last12.income - last12.expense) / last12.income) * 100 : 0

  // With zero data the half-dozen Recharts render as blank boxes, which looks
  // broken. Detect the "essentially empty" case — no money movement over the
  // last 12 months and no recorded net worth — and show a friendly card
  // instead of the charts.
  const hasData = last12.income > 0 || last12.expense > 0 || netWorth.gross !== 0

  if (!hasData) {
    return (
      <div className="flex min-h-0 flex-col gap-3">
        <header className="min-w-0">
          <h1 className="text-xl font-semibold tracking-tight sm:text-2xl">
            {t('reflect.title', 'Reflect')}
          </h1>
          <p className="mt-0.5 text-xs text-muted-foreground">
            {t('reflect.subtitle', 'Long-window analytics — how your money has actually moved.')}
          </p>
        </header>
        <Card>
          <CardContent className="flex flex-col items-center justify-center gap-3 py-16 text-center">
            <LineChart className="h-10 w-10 text-muted-foreground/60" aria-hidden />
            <h2 className="text-base font-medium">
              {t('reflect.emptyTitle', 'Not enough data yet')}
            </h2>
            <p className="max-w-sm text-sm text-muted-foreground">
              {t(
                'reflect.emptyBody',
                'Come back after recording some transactions — your analytics will appear here.',
              )}
            </p>
          </CardContent>
        </Card>
      </div>
    )
  }

  return (
    <div className="flex min-h-0 flex-col gap-3">
      <header className="min-w-0">
        <h1 className="text-xl font-semibold tracking-tight sm:text-2xl">
          {t('reflect.title', 'Reflect')}
        </h1>
        <p className="mt-0.5 text-xs text-muted-foreground">
          {t('reflect.subtitle', 'Long-window analytics — how your money has actually moved.')}
        </p>
      </header>

      <div className="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-5">
        <KpiCard
          title={t('reflect.netWorth', 'Net worth')}
          value={formatCurrency(netWorth.net)}
          hint={`${t('kpi.grossPrefix', 'Gross')} ${formatCurrency(netWorth.gross)}`}
          icon={Wallet}
        />
        <KpiCard
          title={t('reflect.income12mo', 'Income (12mo)')}
          value={formatCurrency(last12.income)}
          icon={TrendingUp}
          tone="positive"
        />
        <KpiCard
          title={t('reflect.spending12mo', 'Spending (12mo)')}
          value={formatCurrency(last12.expense)}
          icon={TrendingDown}
          tone="negative"
        />
        <KpiCard
          title={t('reflect.ageOfMoney', 'Age of money')}
          value={ageOfMoney === null ? '—' : `${Math.round(ageOfMoney)} ${t('reflect.days', 'd')}`}
          hint={t('reflect.savingsRateHint', '{pct} savings rate').replace(
            '{pct}',
            `${savingsRate >= 0 ? '+' : ''}${savingsRate.toFixed(0)}%`,
          )}
          icon={Hourglass}
        />
        <div className="col-span-2 md:col-span-1">
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
        </div>
      </div>

      <WeeklyHeatmap rows={dailyByCategory} weeks={HEATMAP_WEEKS} />

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

      <div className="grid grid-cols-1 gap-3 md:grid-cols-2 xl:grid-cols-4">
        <MonthForecastCard leftToSpend={leftToSpend} />
        <CategoryMoversCard series={categoryTrends} />
        <RecurringSplitCard subscriptions={subscriptions} avgMonthlySpend={last12.expense / 12} />
        <SpendingAnomaliesCard rows={dailyByCategory} />
      </div>

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
        <div className="min-h-[340px] lg:col-span-12 lg:min-h-0">
          <CategoryTrendsChart data={categoryTrends} />
        </div>
        <div className="min-h-[240px] lg:col-span-5 lg:min-h-0">
          <CategoryPie
            data={monthByCategory}
            uncategorizedCount={uncategorizedCount}
            title={t('dashboard.byCategory', 'This month by category')}
          />
        </div>
        <div className="min-h-[240px] lg:col-span-7 lg:min-h-0">
          <TopExpensesCard
            initial={topSpendInitial}
            categories={topSpendCategories}
            defaultDays={30}
            onFetchTopSpend={fetchTopSpend}
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
