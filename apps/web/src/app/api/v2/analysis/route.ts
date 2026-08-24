import { NextResponse } from 'next/server'
import { queries } from '@/db/client'
import { authorizeApi } from '@/server/api-auth'

export const dynamic = 'force-dynamic'

/** The Analyse tab's feed — the Postgres twin of the desktop route. */
export async function GET(request: Request) {
  if (!(await authorizeApi(request))) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

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

  const categoryIds = Object.fromEntries(
    groups.flatMap((g) => g.categories.map((c) => [`${g.name}/${c.name}`, c.id])),
  )

  return NextResponse.json(
    {
      flows,
      categories,
      categoryIds,
      categorySeries,
      dailySpend,
      subscriptions,
      savings,
      ageOfMoney,
    },
    { headers: { 'cache-control': 'no-store' } },
  )
}
