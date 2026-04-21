import { Suspense } from 'react'
import { BurnRateCard } from '@florin/core/components/dashboard/burn-rate-card'
import { CategoryPie } from '@florin/core/components/dashboard/category-pie'
import { DataSourcePill } from '@florin/core/components/dashboard/data-source-pill'
import { IncomeVsSpendingCard } from '@florin/core/components/dashboard/income-vs-spending-card'
import { LeftToSpendCard } from '@florin/core/components/dashboard/left-to-spend-card'
import { NetWorthCard } from '@florin/core/components/dashboard/net-worth-card'
import { PatrimonyChart } from '@florin/core/components/dashboard/patrimony-chart'
import { SafetyGaugeCard } from '@florin/core/components/dashboard/safety-gauge-card'
import { SyncAllButton } from '@florin/core/components/dashboard/sync-all-button'
import { TopExpensesCard } from '@florin/core/components/dashboard/top-expenses-card'
import { OnboardingBanner } from '@florin/core/components/onboarding/onboarding-banner'
import { queries } from '@/db/client'
import { getServerT } from '@/lib/locale'
import { syncAllBanks } from '@/server/actions/banking'
import { fetchTopExpenses } from '@/server/actions/dashboard'

function CardSkeleton({ className }: { className?: string }) {
  return (
    <div
      className={`animate-pulse rounded-xl bg-muted/40 ring-1 ring-foreground/10 ${className ?? 'h-full w-full'}`}
      aria-hidden="true"
    />
  )
}

async function OnboardingBannerServer() {
  const accounts = await queries.listAccounts()
  return <OnboardingBanner accountCount={accounts.length} />
}

async function SyncAllButtonServer() {
  return <SyncAllButton onSyncAllBanks={syncAllBanks} />
}

async function DataSourcePillServer() {
  const [info, t] = await Promise.all([queries.getDataSourceInfo(), getServerT()])
  return (
    <DataSourcePill
      info={info}
      labels={{
        bankApiLive: t('dashboard.bankApiLive', 'Bank API · live'),
        bankApiOffline: t('dashboard.bankApiOffline', 'Bank API · offline'),
      }}
    />
  )
}

async function NetWorthCardServer() {
  const [nw, t] = await Promise.all([queries.getNetWorth(), getServerT()])
  return (
    <NetWorthCard
      gross={nw.gross}
      liability={nw.liability}
      net={nw.net}
      netMonthAgo={nw.netMonthAgo}
      title={t('kpi.netWorth', 'Net worth')}
      grossLabel={t('kpi.grossPrefix', 'Gross')}
      debtLabel={t('kpi.debtPrefix', '− Debt')}
      vsLastMonthLabel={t('kpi.vsLastMonth', 'vs last month')}
    />
  )
}

async function BurnRateCardServer() {
  const now = new Date()
  const month = String(now.getMonth() + 1).padStart(2, '0')
  const year = now.getFullYear()
  const [thisMonth, avg, t] = await Promise.all([
    queries.getMonthBurn(),
    queries.getAvgMonthlyBurn(6),
    getServerT(),
  ])
  return (
    <BurnRateCard
      thisMonth={thisMonth}
      avg={avg}
      href={{
        pathname: '/transactions',
        query: { from: `${year}-${month}-01`, direction: 'expense' },
      }}
      title={t('kpi.burnThisMonth', 'Burn this month')}
    />
  )
}

async function SafetyGaugeCardServer() {
  const [nw, avgBurn, t] = await Promise.all([
    queries.getNetWorth(),
    queries.getAvgMonthlyBurn(6),
    getServerT(),
  ])
  return (
    <SafetyGaugeCard
      net={nw.net}
      avgBurn={avgBurn}
      title={t('kpi.safetyGauge', 'Safety gauge')}
      hint={t('kpi.safetyGaugeHint', 'How long net worth covers your average burn rate')}
      monthsLabel={t('kpi.months', 'months')}
    />
  )
}

async function LeftToSpendCardServer() {
  const [lts, t] = await Promise.all([queries.getLeftToSpendThisMonth(), getServerT()])
  return (
    <LeftToSpendCard
      title={t('kpi.leftToSpend', 'Left to spend')}
      monthIncome={lts.monthIncome}
      monthSpent={lts.monthSpent}
      leftToSpend={lts.leftToSpend}
      dailyAvgSpent={lts.dailyAvgSpent}
      dailyBudgetRemaining={lts.dailyBudgetRemaining}
      daysRemaining={lts.daysRemaining}
      hintCategory={
        lts.salaryCategoryName
          ? t(
              'kpi.leftToSpendCategory',
              { category: lts.salaryCategoryName },
              'Based on “{category}”',
            )
          : undefined
      }
      hintNoIncome={t('kpi.leftToSpendNoIncome', 'No salary detected in the last 90 days.')}
      dailyAvgLabel={t('kpi.dailyAvg', '/day avg')}
      dailyRemainingLabel={(days) =>
        t('kpi.dailyRemaining', { days }, '/day · {days} days left')
      }
    />
  )
}

async function TopExpensesCardServer() {
  const [initial, categoryList] = await Promise.all([
    queries.getTopExpenses(10, 30),
    queries.listCategoriesFlat(),
  ])
  const serialized = initial.map((e) => ({
    id: e.id,
    payee: e.payee,
    date: e.date.toISOString().slice(0, 10),
    amount: Number(e.amount),
    categoryName: e.categoryName ?? null,
  }))
  const categories = categoryList.map((c) => ({
    id: c.id,
    name: c.name,
    emoji: c.emoji,
    groupName: c.groupName,
  }))
  return (
    <TopExpensesCard
      initial={serialized}
      categories={categories}
      defaultDays={30}
      onFetchTopExpenses={fetchTopExpenses}
    />
  )
}

async function PatrimonyChartServer() {
  const [data, t] = await Promise.all([queries.getPatrimonyTimeSeries(12), getServerT()])
  return (
    <PatrimonyChart
      data={data}
      title={t('dashboard.patrimony', 'Patrimony')}
      allHistoryLabel={t('dashboard.allHistory', 'All history')}
      showForecastLabel={t('dashboard.showForecast', 'Show forecast')}
      hideForecastLabel={t('dashboard.hideForecast', 'Hide forecast')}
    />
  )
}

async function IncomeVsSpendingServer() {
  const [data, t] = await Promise.all([queries.getMonthlyFlows(12), getServerT()])
  return (
    <IncomeVsSpendingCard
      data={data}
      title={t('dashboard.incomeVsSpending', 'Income vs spending')}
      subtitle={t('dashboard.last12Months', 'Last 12 months')}
    />
  )
}

async function CategoryPieServer() {
  const [data, uncategorizedCount, t] = await Promise.all([
    queries.getMonthByCategory(),
    queries.countUncategorizedExpensesThisMonth(),
    getServerT(),
  ])
  return (
    <CategoryPie
      data={data}
      uncategorizedCount={uncategorizedCount}
      title={t('dashboard.byCategory', 'This month by category')}
    />
  )
}

export default async function DashboardPage() {
  const t = await getServerT()
  return (
    <div className="flex min-h-0 flex-col gap-3 lg:h-full">
      <Suspense fallback={null}>
        <OnboardingBannerServer />
      </Suspense>
      <header className="flex flex-wrap items-center justify-between gap-3">
        <div className="min-w-0">
          <h1 className="text-xl font-semibold tracking-tight sm:text-2xl">
            {t('dashboard.title', 'Dashboard')}
          </h1>
          <p className="mt-0.5 text-xs text-muted-foreground">
            {t('dashboard.subtitle', 'Your money, in one screen')}
          </p>
        </div>
        <div className="flex items-center gap-2">
          <SyncAllButtonServer />
          <Suspense
            fallback={
              <span className="inline-block h-6 w-32 animate-pulse rounded-full bg-muted" />
            }
          >
            <DataSourcePillServer />
          </Suspense>
        </div>
      </header>

      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 md:grid-cols-4">
        <Suspense fallback={<CardSkeleton className="h-[120px]" />}>
          <NetWorthCardServer />
        </Suspense>
        <Suspense fallback={<CardSkeleton className="h-[120px]" />}>
          <BurnRateCardServer />
        </Suspense>
        <Suspense fallback={<CardSkeleton className="h-[120px]" />}>
          <LeftToSpendCardServer />
        </Suspense>
        <Suspense fallback={<CardSkeleton className="h-[120px]" />}>
          <SafetyGaugeCardServer />
        </Suspense>
      </div>

      <div className="grid min-h-0 grid-cols-1 gap-3 lg:flex-1 lg:grid-cols-12">
        <div className="grid min-h-0 grid-cols-1 gap-3 lg:col-span-7 lg:grid-rows-2">
          <div className="min-h-[240px] lg:min-h-0">
            <Suspense fallback={<CardSkeleton />}>
              <PatrimonyChartServer />
            </Suspense>
          </div>
          <div className="min-h-[240px] lg:min-h-0">
            <Suspense fallback={<CardSkeleton />}>
              <IncomeVsSpendingServer />
            </Suspense>
          </div>
        </div>
        <div className="grid min-h-0 grid-cols-1 gap-3 lg:col-span-5 lg:grid-rows-2">
          <div className="min-h-[240px] lg:min-h-0">
            <Suspense fallback={<CardSkeleton />}>
              <TopExpensesCardServer />
            </Suspense>
          </div>
          <div className="min-h-[240px] lg:min-h-0">
            <Suspense fallback={<CardSkeleton />}>
              <CategoryPieServer />
            </Suspense>
          </div>
        </div>
      </div>
    </div>
  )
}
