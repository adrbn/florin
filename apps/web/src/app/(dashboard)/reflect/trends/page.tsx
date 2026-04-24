import { CategoryBreakdownChart } from '@florin/core/components/reflect/category-breakdown-chart'
import { CategoryTrendsChart } from '@florin/core/components/reflect/category-trends-chart'
import { queries } from '@/db/client'
import { getServerT } from '@/lib/locale'

// Deep-dive on spending trends by category. Gets the full page so the
// multi-line chart can breathe — the overview route packs five sections
// into one screen, which makes this one cramped.
export const dynamic = 'force-dynamic'

export default async function ReflectTrendsPage() {
  const t = await getServerT()
  const [categoryTrends, categoryShare] = await Promise.all([
    queries.getCategorySpendingSeries(24),
    queries.getCategoryBreakdown(90),
  ])

  return (
    <div className="flex min-h-0 flex-col gap-3">
      <header className="min-w-0">
        <h1 className="text-xl font-semibold tracking-tight sm:text-2xl">
          {t('reflect.trends.title', 'Spending trends')}
        </h1>
        <p className="mt-0.5 text-xs text-muted-foreground">
          {t(
            'reflect.trends.subtitle',
            'Per-category evolution over time. Use the window selector to zoom in on a specific range.',
          )}
        </p>
      </header>

      <CategoryTrendsChart data={categoryTrends} />

      <div className="min-h-[240px]">
        <CategoryBreakdownChart
          data={categoryShare}
          windowLabel={t('dashboard.lastNDays', 'Last {n} days').replace('{n}', '90')}
          titlePrefix={
            t('reflect.spendingBreakdown', 'Spending breakdown — last 90 days').split(' — ')[0] ??
            'Spending breakdown'
          }
        />
      </div>
    </div>
  )
}
