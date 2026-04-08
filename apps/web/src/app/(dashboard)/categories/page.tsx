import { CategoriesEditor } from '@/components/categories/categories-editor'
import { CategorySpendList } from '@/components/categories/category-spend-list'
import { listCategoriesByGroup } from '@/server/actions/categories'
import { getMonthByCategory } from '@/server/queries/dashboard'

export default async function CategoriesPage() {
  const [groups, monthBreakdown] = await Promise.all([
    listCategoriesByGroup(),
    getMonthByCategory(),
  ])

  // Map drizzle's `with` rows into the simpler shape the client editor expects.
  const editorGroups = groups.map((g) => ({
    id: g.id,
    name: g.name,
    kind: g.kind,
    color: g.color,
    categories: g.categories.map((c) => ({
      id: c.id,
      name: c.name,
      emoji: c.emoji,
      isFixed: c.isFixed,
    })),
  }))

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Categories</h1>
        <p className="text-muted-foreground">
          Organize spending into buckets. Edit names, recolor groups, mark recurring categories as
          fixed, or delete the ones you don't use.
        </p>
      </div>

      <div className="grid gap-6 lg:grid-cols-3">
        <div className="lg:col-span-2">
          <CategoriesEditor groups={editorGroups} />
        </div>
        <div>
          <CategorySpendList items={monthBreakdown} />
        </div>
      </div>
    </div>
  )
}
