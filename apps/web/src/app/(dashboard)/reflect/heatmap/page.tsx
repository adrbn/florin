import { WeeklyHeatmap } from '@florin/core/components/reflect/weekly-heatmap'
import { queries } from '@/db/client'
import { getServerT } from '@/lib/locale'

const HEATMAP_WEEKS = 52
const HEATMAP_WINDOW_DAYS = HEATMAP_WEEKS * 7 + 7

export const dynamic = 'force-dynamic'

export default async function ReflectHeatmapPage() {
  const t = await getServerT()
  const dailyByCategory = await queries.getDailySpendByCategory(HEATMAP_WINDOW_DAYS)

  return (
    <div className="flex min-h-0 flex-col gap-3">
      <header className="min-w-0">
        <h1 className="text-xl font-semibold tracking-tight sm:text-2xl">
          {t('reflect.heatmap.title', 'Spending heatmap')}
        </h1>
        <p className="mt-0.5 text-xs text-muted-foreground">
          {t(
            'reflect.heatmap.pageSubtitle',
            'One cell per day over the last year. Darker = higher spend. Click a cell to inspect that day.',
          )}
        </p>
      </header>

      <WeeklyHeatmap rows={dailyByCategory} weeks={HEATMAP_WEEKS} />
    </div>
  )
}
