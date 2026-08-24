import { NextResponse } from 'next/server'
import { queries } from '@/db/client'

export const dynamic = 'force-dynamic'

/**
 * The Analyse tab's feed.
 *
 * Exactly the eight queries `/m/reflect` runs, returned unwrapped — the native
 * screen renders the same figures the web one does, and neither derives
 * anything the other doesn't. `categoryIds` is assembled here for the same
 * reason the page adapter assembles it: `getCategoryBreakdown` has no ids, and
 * widening it would touch a query the shipping v1 screens also depend on.
 */
export async function GET() {
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
