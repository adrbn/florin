import { asc, eq } from 'drizzle-orm'
import { db, queries } from '@/db/client'
import { categories, categoryGroups } from '@/db/schema'
import { TopExpensesList } from './top-expenses-list'

const DEFAULT_DAYS = 30

export async function TopExpensesCard() {
  // Server-side initial render at the default 30-day window. The client
  // component takes over filtering from here via the `fetchTopExpenses`
  // server action.
  const initial = await queries.getTopExpenses(5, DEFAULT_DAYS, null)

  // Categories list for the filter dropdown — only expense categories,
  // joined with their group for prettier labels ("Group / Name").
  const categoryRows = await db
    .select({
      id: categories.id,
      name: categories.name,
      emoji: categories.emoji,
      groupName: categoryGroups.name,
    })
    .from(categories)
    .innerJoin(categoryGroups, eq(categories.groupId, categoryGroups.id))
    .where(eq(categoryGroups.kind, 'expense'))
    .orderBy(asc(categoryGroups.displayOrder), asc(categoryGroups.name), asc(categories.name))

  return (
    <TopExpensesList
      initial={initial.map((e) => ({ ...e, date: e.date.toISOString() }))}
      categories={categoryRows}
      defaultDays={DEFAULT_DAYS}
    />
  )
}
