import { Suspense } from 'react'
import { AllocationDonut } from '@florin/core/components/dashboard/allocation-donut'
import { BurnRateCard } from '@florin/core/components/dashboard/burn-rate-card'
import { GoalCard } from '@florin/core/components/dashboard/goal-card'
import { DataSourcePill } from '@florin/core/components/dashboard/data-source-pill'
import { IncomeVsSpendingCard } from '@florin/core/components/dashboard/income-vs-spending-card'
import { LeftToSpendCard } from '@florin/core/components/dashboard/left-to-spend-card'
import { NetWorthCard } from '@florin/core/components/dashboard/net-worth-card'
import { PatrimonyChart } from '@florin/core/components/dashboard/patrimony-chart'
import { SafetyGaugeCard } from '@florin/core/components/dashboard/safety-gauge-card'
import { SyncAllButton } from '@florin/core/components/dashboard/sync-all-button'
import { MonthForecastCard } from '@florin/core/components/reflect/month-forecast-card'
import { SavingsRateRolling } from '@florin/core/components/reflect/savings-rate-rolling'
import { formatCurrency } from '@florin/core/lib/format'
import { OnboardingBanner } from '@florin/core/components/onboarding/onboarding-banner'
import { DashboardOnboarding } from '@florin/core/components/onboarding/dashboard-onboarding'
import { projectGoal } from '@florin/core/lib/goal'
import { monthlyNetWorthTrend } from '@florin/core/lib/trend'
import { queries } from '@/db/client'
import { getAppConfig } from '@/lib/app-config'
import { getServerT, getUserLocale } from '@/lib/locale'
import { syncAllBanks } from '@/server/actions/banking'
import { toLocaleTag } from '@florin/core/i18n'

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

/**
 * "First steps" checklist + one-time spotlight tour for a new user. Every flag
 * comes from a query that already exists, so this adds no DB surface. Renders
 * nothing once the user is set up (the component self-hides).
 */
async function DashboardOnboardingServer() {
  const [accounts, txCount, needsReviewCount] = await Promise.all([
    queries.listAccounts(),
    queries.countTransactions(),
    queries.countNeedsReview(),
  ])
  return (
    <DashboardOnboarding
      hasAccount={accounts.length > 0}
      hasBankSync={accounts.some((a) => a.syncProvider === 'enable_banking')}
      hasTransactions={txCount > 0}
      needsReviewCount={needsReviewCount}
    />
  )
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
  const [nw, series, t] = await Promise.all([
    queries.getNetWorth(),
    queries.getPatrimonyTimeSeries(12),
    getServerT(),
  ])
  const monthlyTrend = monthlyNetWorthTrend(series)
  return (
    <NetWorthCard
      gross={nw.gross}
      liability={nw.liability}
      net={nw.net}
      monthlyTrend={monthlyTrend}
      title={t('kpi.netWorth', 'Net worth')}
      grossLabel={t('kpi.grossPrefix', 'Gross')}
      debtLabel={t('kpi.debtPrefix', '− Debt')}
      monthlyTrendLabel={t('kpi.monthlyTrend', '/mo trend')}
    />
  )
}

async function BurnRateCardServer() {
  const now = new Date()
  const month = String(now.getMonth() + 1).padStart(2, '0')
  const year = now.getFullYear()
  const [thisMonth, avg, t] = await Promise.all([
    // Gross spend so the "spent this month" figure reads what actually went
    // out, not a near-zero net when a reimbursement offsets early expenses.
    queries.getMonthBurn({ gross: true }),
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
      hint={t('kpi.sixMoAvg', { amount: formatCurrency(avg) }, '6-mo avg: {amount}')}
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
      title={t('kpi.leftToSpend', 'Monthly margin')}
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
      perDayLabel={t('kpi.perDay', '/day')}
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

async function AllocationDonutServer() {
  const [allocation, locale] = await Promise.all([
    queries.getNetWorthAllocation(),
    getUserLocale(),
  ])
  const localeTag = toLocaleTag(locale)
  return <AllocationDonut allocation={allocation} locale={localeTag} />
}

async function GoalCardServer() {
  const [snapshot, locale] = await Promise.all([
    queries.getInvestmentSnapshot(),
    getUserLocale(),
  ])
  const cfg = await getAppConfig()
  // A stated "I invest X/month" (config) beats guessing from history. Falls
  // back to the detected rate when the user hasn't set a planned amount.
  const monthlyContribution =
    cfg.plannedMonthlyInvestment > 0 ? cfg.plannedMonthlyInvestment : snapshot.monthlyContribution
  // Only render when there's actual investment activity — otherwise a
  // non-investor would just see an empty goal card.
  if (snapshot.investedValue <= 0 && monthlyContribution <= 0) return null
  const localeTag = toLocaleTag(locale)
  const projection = projectGoal({
    currentValue: snapshot.investedValue,
    monthlyContribution,
    annualReturnPct: cfg.goalReturnPct,
    target: cfg.goalTarget,
  })
  return <GoalCard projection={projection} locale={localeTag} />
}

async function SavingsRateRollingServer() {
  const [rates, t] = await Promise.all([queries.getSavingsRates(), getServerT()])
  return (
    <SavingsRateRolling
      rates={rates}
      title={t('reflect.savingsRolling', 'Savings rate — rolling')}
      subtitle={t('reflect.savingsRollingSubtitle', 'Saved ÷ income over 3, 6, 12 months.')}
      className="flex h-full flex-col"
      labels={{
        threeMonth: t('reflect.threeMonth', '3 mo'),
        sixMonth: t('reflect.sixMonth', '6 mo'),
        twelveMonth: t('reflect.twelveMonth', '12 mo'),
        noData: t('reflect.noIncome', 'no income'),
      }}
    />
  )
}

async function MonthForecastServer() {
  const lts = await queries.getLeftToSpendThisMonth()
  return <MonthForecastCard leftToSpend={lts} />
}

export default async function DashboardPage() {
  const t = await getServerT()
  return (
    <div className="flex min-h-0 flex-col gap-3 lg:h-full">
      <Suspense fallback={null}>
        <OnboardingBannerServer />
      </Suspense>
      <Suspense fallback={null}>
        <DashboardOnboardingServer />
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
        <div data-tour="sync" className="flex items-center gap-2">
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

      <div data-tour="kpis" className="grid grid-cols-1 gap-3 sm:grid-cols-2 md:grid-cols-4">
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

      {/*
       * Below the KPI strip the body fills the rest of the viewport with no void.
       * The two big charts (Patrimoine, Revenus vs dépenses) take the lion's
       * share of the height so neither feels crushed; underneath, four
       * near-square quarter tiles (Répartition, Taux d'épargne, Prévision,
       * Objectif) sit on one short row. On mobile everything stacks + scrolls.
       */}
      <div className="flex min-h-0 flex-1 flex-col gap-3">
        <div data-tour="charts" className="grid min-h-0 flex-1 grid-cols-1 gap-3 [grid-auto-rows:minmax(280px,1fr)] lg:grid-cols-3 lg:[grid-auto-rows:minmax(0,1fr)]">
          <div className="min-h-0 h-full lg:col-span-2">
            <Suspense fallback={<CardSkeleton />}>
              <PatrimonyChartServer />
            </Suspense>
          </div>
          <div className="min-h-0 h-full lg:col-span-1">
            <Suspense fallback={<CardSkeleton />}>
              <IncomeVsSpendingServer />
            </Suspense>
          </div>
        </div>
        {/*
         * The tall fixed row height ONLY applies at xl, where all four tiles sit
         * on ONE row. Below xl the grid is 2-col — two rows — and forcing 2×312px
         * would eat the whole viewport and collapse the flex-1 charts to zero.
         * There the rows size to content instead (no clipping, charts survive).
         */}
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-4 xl:[grid-auto-rows:clamp(280px,30vh,312px)]">
          <div className="min-h-0 h-full">
            <Suspense fallback={<CardSkeleton className="h-[300px]" />}>
              <AllocationDonutServer />
            </Suspense>
          </div>
          <div className="min-h-0 h-full">
            <Suspense fallback={<CardSkeleton className="h-[300px]" />}>
              <SavingsRateRollingServer />
            </Suspense>
          </div>
          <div className="min-h-0 h-full">
            <Suspense fallback={<CardSkeleton className="h-[300px]" />}>
              <MonthForecastServer />
            </Suspense>
          </div>
          <div className="min-h-0 h-full">
            <Suspense fallback={<CardSkeleton className="h-[300px]" />}>
              <GoalCardServer />
            </Suspense>
          </div>
        </div>
      </div>
    </div>
  )
}
