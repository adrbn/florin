import Link from 'next/link'
import { Card, CardContent, CardHeader, CardTitle } from '../ui/card'
import { formatCurrency } from '../../lib/format/currency'

interface CategorySpendListProps {
  items: ReadonlyArray<{
    categoryId?: string
    groupName: string
    categoryName: string
    emoji: string | null
    total: number
    color: string | null
  }>
  title?: string
  emptyMessage?: string
}

/**
 * Compact "spend by category this month" sidebar widget. Each row gets a
 * proportional bar so the user can eyeball where money is going at a glance.
 * Clicking a row drills into /transactions filtered by that category and the
 * current month.
 */
export function CategorySpendList({
  items,
  title = 'This month — by category',
  emptyMessage = 'No categorized expenses this month yet.',
}: CategorySpendListProps) {
  const max = items.reduce((m, i) => Math.max(m, i.total), 0)
  const now = new Date()
  const year = now.getFullYear()
  const month = String(now.getMonth() + 1).padStart(2, '0')
  const lastDay = new Date(year, now.getMonth() + 1, 0).getDate()
  const from = `${year}-${month}-01`
  const to = `${year}-${month}-${String(lastDay).padStart(2, '0')}`

  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-sm">{title}</CardTitle>
      </CardHeader>
      <CardContent>
        {items.length === 0 ? (
          <p className="text-xs text-muted-foreground">{emptyMessage}</p>
        ) : (
          <ul className="space-y-2">
            {items.slice(0, 10).map((item) => {
              const pct = max > 0 ? (item.total / max) * 100 : 0
              const row = (
                <>
                  <div className="flex items-center justify-between gap-2 text-xs">
                    <span className="flex items-center gap-1.5 truncate text-foreground">
                      {item.emoji && <span aria-hidden>{item.emoji}</span>}
                      <span className="truncate">{item.categoryName}</span>
                      <span className="text-[10px] text-muted-foreground">· {item.groupName}</span>
                    </span>
                    <span className="tabular-nums text-foreground">
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
                </>
              )
              const key = `${item.groupName}/${item.categoryName}`
              return (
                <li key={key}>
                  {item.categoryId ? (
                    <Link
                      href={{
                        pathname: '/transactions',
                        query: {
                          from,
                          to,
                          direction: 'expense',
                          categoryId: item.categoryId,
                        },
                      }}
                      className="block space-y-1 rounded-md -mx-1.5 px-1.5 py-1 transition-colors hover:bg-muted/60 focus:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                      aria-label={`${item.categoryName} — view transactions`}
                    >
                      {row}
                    </Link>
                  ) : (
                    <div className="space-y-1">{row}</div>
                  )}
                </li>
              )
            })}
          </ul>
        )}
      </CardContent>
    </Card>
  )
}
