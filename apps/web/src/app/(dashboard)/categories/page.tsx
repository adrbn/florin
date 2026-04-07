import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { listCategoriesByGroup } from '@/server/actions/categories'

export default async function CategoriesPage() {
  const groups = await listCategoriesByGroup()

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Categories</h1>
        <p className="text-muted-foreground">
          Organized by group. Fixed categories repeat each month.
        </p>
      </div>

      {groups.length === 0 ? (
        <Card>
          <CardContent className="py-12 text-center text-muted-foreground">
            No categories defined yet.
          </CardContent>
        </Card>
      ) : (
        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
          {groups.map((group) => (
            <Card key={group.id}>
              <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-3">
                <CardTitle className="text-base">{group.name}</CardTitle>
                <Badge variant="outline">{group.kind}</Badge>
              </CardHeader>
              <CardContent>
                {group.categories.length === 0 ? (
                  <p className="text-xs text-muted-foreground">No categories yet.</p>
                ) : (
                  <ul className="space-y-1.5">
                    {group.categories.map((category) => (
                      <li
                        key={category.id}
                        className="flex items-center justify-between gap-2 text-sm"
                      >
                        <span className="flex items-center gap-2">
                          {category.emoji && (
                            <span className="text-base" aria-hidden>
                              {category.emoji}
                            </span>
                          )}
                          <span>{category.name}</span>
                        </span>
                        {category.isFixed && (
                          <Badge variant="secondary" className="text-[10px]">
                            fixed
                          </Badge>
                        )}
                      </li>
                    ))}
                  </ul>
                )}
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  )
}
