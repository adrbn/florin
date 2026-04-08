import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { formatCurrency } from '@/lib/format/currency'

interface CategorySpendListProps {
  items: ReadonlyArray<{
    groupName: string
    categoryName: string
    emoji: string | null
    total: number
    color: string | null
  }>
}

/**
 * Compact "spend by category this month" sidebar widget. Each row gets a
 * proportional bar so the user can eyeball where money is going at a glance.
 */
export function CategorySpendList({ items }: CategorySpendListProps) {
  const max = items.reduce((m, i) => Math.max(m, i.total), 0)

  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-sm">This month — by category</CardTitle>
      </CardHeader>
      <CardContent>
        {items.length === 0 ? (
          <p className="text-xs text-muted-foreground">No categorized expenses this month yet.</p>
        ) : (
          <ul className="space-y-2">
            {items.slice(0, 10).map((item) => {
              const pct = max > 0 ? (item.total / max) * 100 : 0
              return (
                <li key={`${item.groupName}/${item.categoryName}`} className="space-y-1">
                  <div className="flex items-center justify-between gap-2 text-xs">
                    <span className="flex items-center gap-1.5 truncate text-foreground">
                      {item.emoji && <span aria-hidden>{item.emoji}</span>}
                      <span className="truncate">{item.categoryName}</span>
                      <span className="text-[10px] text-muted-foreground">· {item.groupName}</span>
                    </span>
                    <span className="font-mono tabular-nums text-foreground">
                      {formatCurrency(item.total)}
                    </span>
                  </div>
                  <div className="h-1 overflow-hidden rounded-full bg-muted">
                    <div
                      className="h-full bg-primary/70"
                      style={{ width: `${pct}%` }}
                      aria-hidden
                    />
                  </div>
                </li>
              )
            })}
          </ul>
        )}
      </CardContent>
    </Card>
  )
}
