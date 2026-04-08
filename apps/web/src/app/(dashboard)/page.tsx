import { Suspense } from 'react'
import { BurnRateCard } from '@/components/dashboard/burn-rate-card'
import { CategoryPie } from '@/components/dashboard/category-pie'
import { DataSourcePill } from '@/components/dashboard/data-source-pill'
import { IncomeVsSpendingCard } from '@/components/dashboard/income-vs-spending-card'
import { NetWorthCard } from '@/components/dashboard/net-worth-card'
import { PatrimonyChart } from '@/components/dashboard/patrimony-chart'
import { SafetyGaugeCard } from '@/components/dashboard/safety-gauge-card'
import { SyncAllButton } from '@/components/dashboard/sync-all-button'
import { TopExpensesCard } from '@/components/dashboard/top-expenses-card'
import { OnboardingBanner } from '@/components/onboarding/onboarding-banner'
import {
  countUncategorizedExpensesThisMonth,
  getMonthByCategory,
  getPatrimonyTimeSeries,
} from '@/server/queries/dashboard'
import { getMonthlyFlows } from '@/server/queries/reflect'

function CardSkeleton({ className }: { className?: string }) {
  // Match the real Card primitive (rounded-xl, ring-foreground/10) so the
  // skeleton and the loaded card have the same silhouette and there's no
  // jump when Suspense resolves.
  return (
    <div
      className={`animate-pulse rounded-xl bg-muted/40 ring-1 ring-foreground/10 ${className ?? 'h-full w-full'}`}
      aria-hidden="true"
    />
  )
}

async function PatrimonyChartServer() {
  const data = await getPatrimonyTimeSeries(12)
  return <PatrimonyChart data={data} />
}

async function IncomeVsSpendingServer() {
  const data = await getMonthlyFlows(12)
  return <IncomeVsSpendingCard data={data} />
}

async function CategoryPieServer() {
  const [data, uncategorizedCount] = await Promise.all([
    getMonthByCategory(),
    countUncategorizedExpensesThisMonth(),
  ])
  return <CategoryPie data={data} uncategorizedCount={uncategorizedCount} />
}

export default function DashboardPage() {
  // The dashboard is the one page we actively try to fit in a single
  // viewport. We let the parent <main> own scrolling and use min-h-0 on
  // every nested flex child so the chart containers can actually shrink
  // instead of pushing the page taller than the viewport. On mobile we
  // let it scroll naturally because the KPI strip + four charts can't
  // physically fit on a 700px-tall phone.
  return (
    <div className="flex min-h-0 flex-col gap-3 lg:h-full">
      <Suspense fallback={null}>
        <OnboardingBanner />
      </Suspense>
      <header className="flex flex-wrap items-center justify-between gap-3">
        <div className="min-w-0">
          <h1 className="text-xl font-semibold tracking-tight sm:text-2xl">Dashboard</h1>
          <p className="mt-0.5 text-xs text-muted-foreground">Your money, in one screen</p>
        </div>
        <div className="flex items-center gap-2">
          <SyncAllButton />
          <Suspense
            fallback={
              <span className="inline-block h-6 w-32 animate-pulse rounded-full bg-muted" />
            }
          >
            <DataSourcePill />
          </Suspense>
        </div>
      </header>

      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 md:grid-cols-3">
        <Suspense fallback={<CardSkeleton className="h-[84px]" />}>
          <NetWorthCard />
        </Suspense>
        <Suspense fallback={<CardSkeleton className="h-[84px]" />}>
          <BurnRateCard />
        </Suspense>
        <Suspense fallback={<CardSkeleton className="h-[84px]" />}>
          <SafetyGaugeCard />
        </Suspense>
      </div>

      {/*
        Desktop layout: 12-column grid, two rows on each side.
          Left column (7 cols):
            row 1 — Patrimony (half as tall as before)
            row 2 — Income vs spending (new)
          Right column (5 cols):
            row 1 — Top expenses
            row 2 — This month by category
        Mobile collapses the whole thing to a single column so each chart
        gets its own breathing room.
      */}
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
              <TopExpensesCard />
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
