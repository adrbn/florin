import { NextResponse } from 'next/server'
import { like, isNull, eq, desc, asc } from 'drizzle-orm'
import { db } from '@/db/client'
import { transactions, accounts, categories, categoryGroups } from '@/db/schema'

export const dynamic = 'force-dynamic'

export async function GET(request: Request) {
  const { searchParams } = new URL(request.url)
  const q = searchParams.get('q')?.trim() ?? ''

  if (q.length < 2) {
    return NextResponse.json({ transactions: [], accounts: [], categories: [] })
  }

  const pattern = `%${q}%`

  const [txResults, accountResults, categoryResults] = await Promise.all([
    db
      .select({
        id: transactions.id,
        payee: transactions.payee,
        amount: transactions.amount,
        date: transactions.occurredAt,
        accountId: transactions.accountId,
      })
      .from(transactions)
      .where(isNull(transactions.deletedAt))
      .orderBy(desc(transactions.occurredAt))
      .limit(50)
      .then((rows) =>
        rows.filter((r) => r.payee.toLowerCase().includes(q.toLowerCase())).slice(0, 8),
      ),
    db
      .select({ id: accounts.id, name: accounts.name, kind: accounts.kind })
      .from(accounts)
      .where(eq(accounts.isArchived, false))
      .then((rows) =>
        rows.filter((r) => r.name.toLowerCase().includes(q.toLowerCase())).slice(0, 5),
      ),
    db
      .select({
        id: categories.id,
        name: categories.name,
        emoji: categories.emoji,
        groupName: categoryGroups.name,
      })
      .from(categories)
      .innerJoin(categoryGroups, eq(categories.groupId, categoryGroups.id))
      .where(eq(categories.isArchived, false))
      .orderBy(asc(categoryGroups.name), asc(categories.name))
      .then((rows) =>
        rows
          .filter(
            (r) =>
              r.name.toLowerCase().includes(q.toLowerCase()) ||
              r.groupName.toLowerCase().includes(q.toLowerCase()),
          )
          .slice(0, 5),
      ),
  ])

  return NextResponse.json({
    transactions: txResults,
    accounts: accountResults,
    categories: categoryResults,
  })
}
