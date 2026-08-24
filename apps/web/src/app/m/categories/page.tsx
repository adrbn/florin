import { CategoriesScreen } from '@florin/core/components/v2/screens/categories'
import { queries } from '@/db/client'

export const dynamic = 'force-dynamic'

export default async function V2Categories() {
  const [groups, monthByCategory] = await Promise.all([
    queries.listCategoriesByGroup(),
    queries.getMonthByCategory(),
  ])
  const spendByCategory = new Map(monthByCategory.map((c) => [c.categoryId, Math.abs(c.total)]))

  return (
    <CategoriesScreen
      groups={groups.map((g) => ({
        id: g.id,
        name: g.name,
        kind: g.kind,
        categories: g.categories.map((c) => ({
          id: c.id,
          name: c.name,
          emoji: c.emoji,
          isFixed: Boolean(c.isFixed),
          monthTotal: spendByCategory.get(c.id) ?? 0,
        })),
      }))}
    />
  )
}
