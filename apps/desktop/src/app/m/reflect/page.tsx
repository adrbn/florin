import { AnalysisScreen } from '@florin/core/components/v2/screens/analysis'
import { queries } from '@/db/client'

export const dynamic = 'force-dynamic'

export default async function V2Analysis() {
  const [flows, categories, categorySeries, dailySpend, subscriptions, savings, ageOfMoney, groups] =
    await Promise.all([
      queries.getMonthlyFlows(12),
      queries.getCategoryBreakdown(30),
      queries.getCategorySpendingSeries(12),
      queries.getDailySpend(365),
      queries.getSubscriptions(),
      queries.getSavingsRates(),
      queries.getAgeOfMoney(),
      queries.listCategoriesByGroup(),
    ])

  // `groupName/categoryName` → id, so a category bar can open its transactions.
  const categoryIds = Object.fromEntries(
    groups.flatMap((g) => g.categories.map((c) => [`${g.name}/${c.name}`, c.id])),
  )

  return (
    <AnalysisScreen
      data={{
        flows,
        categories,
        categoryIds,
        categorySeries,
        dailySpend,
        subscriptions,
        savings,
        ageOfMoney,
      }}
    />
  )
}
