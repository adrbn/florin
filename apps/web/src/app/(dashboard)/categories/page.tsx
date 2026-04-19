import { CategoriesEditor } from '@florin/core/components/categories/categories-editor'
import { CategorySpendList } from '@florin/core/components/categories/category-spend-list'
import { queries } from '@/db/client'
import { getServerT } from '@/lib/locale'
import {
  createCategory,
  updateCategory,
  deleteCategory,
  createCategoryGroup,
  updateCategoryGroup,
  deleteCategoryGroup,
} from '@/server/actions/categories'

export default async function CategoriesPage() {
  const t = await getServerT()
  const [groups, monthBreakdown] = await Promise.all([
    queries.listCategoriesByGroup(),
    queries.getMonthByCategory(),
  ])

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
        <h1 className="text-3xl font-bold tracking-tight">{t('categories.title', 'Categories')}</h1>
        <p className="text-muted-foreground">
          {t(
            'categories.subtitle',
            "Organize spending into buckets. Edit names, recolor groups, mark recurring categories as fixed, or delete the ones you don't use.",
          )}
        </p>
      </div>

      <div className="grid gap-6 lg:grid-cols-3">
        <div className="lg:col-span-2">
          <CategoriesEditor
            groups={editorGroups}
            actions={{
              onCreateCategory: createCategory,
              onUpdateCategory: updateCategory,
              onDeleteCategory: deleteCategory,
              onCreateCategoryGroup: createCategoryGroup,
              onUpdateCategoryGroup: updateCategoryGroup,
              onDeleteCategoryGroup: deleteCategoryGroup,
            }}
          />
        </div>
        <div>
          <CategorySpendList
            items={monthBreakdown}
            title={t('categories.thisMonth', 'This month — by category')}
          />
        </div>
      </div>
    </div>
  )
}
