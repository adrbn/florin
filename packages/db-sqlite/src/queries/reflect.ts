import { and, asc, eq, gte, isNull, sql } from 'drizzle-orm'
import type { SqliteDB } from '../client'
import { accounts, categories, categoryGroups, transactions } from '../schema'
import { getNetWorth } from './dashboard'

import type { MonthlyFlow, CategoryShare, NetWorthPoint } from '@florin/core/types'

export async function getMonthlyFlows(db: SqliteDB, months = 12): Promise<MonthlyFlow[]> {
  const start = formatDate(startOfMonth(addMonths(new Date(), -(months - 1))))
  const rows = await db
    .select({
      month: sql<string>`strftime('%Y-%m', ${transactions.occurredAt})`,
      income: sql<number>`COALESCE(SUM(CASE WHEN ${transactions.amount} > 0 THEN ${transactions.amount} ELSE 0 END), 0)`,
      expense: sql<number>`COALESCE(SUM(CASE WHEN ${transactions.amount} < 0 THEN ${transactions.amount} ELSE 0 END), 0)`,
    })
    .from(transactions)
    .innerJoin(accounts, eq(transactions.accountId, accounts.id))
    .where(
      and(
        isNull(transactions.deletedAt),
        gte(transactions.occurredAt, start),
        sql`${transactions.transferPairId} IS NULL`,
        eq(accounts.isArchived, false),
      ),
    )
    .groupBy(sql`strftime('%Y-%m', ${transactions.occurredAt})`)
    .orderBy(sql`strftime('%Y-%m', ${transactions.occurredAt})`)

  const byMonth = new Map<string, MonthlyFlow>()
  for (const r of rows) {
    const income = Number(r.income)
    const expense = Math.abs(Number(r.expense))
    byMonth.set(r.month, { month: r.month, income, expense, net: income - expense })
  }
  const out: MonthlyFlow[] = []
  for (let i = months - 1; i >= 0; i--) {
    const d = addMonths(new Date(), -i)
    const key = `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`
    out.push(byMonth.get(key) ?? { month: key, income: 0, expense: 0, net: 0 })
  }
  return out
}

export async function getCategoryBreakdown(db: SqliteDB, days = 90): Promise<CategoryShare[]> {
  const start = formatDate(new Date(Date.now() - days * 24 * 60 * 60 * 1000))
  const rows = await db
    .select({
      groupName: categoryGroups.name,
      categoryName: categories.name,
      emoji: categories.emoji,
      total: sql<number>`COALESCE(SUM(${transactions.amount}), 0)`,
    })
    .from(transactions)
    .innerJoin(accounts, eq(transactions.accountId, accounts.id))
    .innerJoin(categories, eq(transactions.categoryId, categories.id))
    .innerJoin(categoryGroups, eq(categories.groupId, categoryGroups.id))
    .where(
      and(
        isNull(transactions.deletedAt),
        gte(transactions.occurredAt, start),
        sql`${transactions.amount} < 0`,
        sql`${transactions.transferPairId} IS NULL`,
        eq(categoryGroups.kind, 'expense'),
        eq(accounts.isArchived, false),
      ),
    )
    .groupBy(categoryGroups.name, categories.name, categories.emoji)
    .orderBy(asc(sql`COALESCE(SUM(${transactions.amount}), 0)`))

  return rows
    .map((r) => ({
      groupName: r.groupName,
      categoryName: r.categoryName,
      emoji: r.emoji,
      total: Math.abs(Number(r.total)),
    }))
    .filter((r) => r.total > 0)
}

export async function getAgeOfMoney(db: SqliteDB, days = 90): Promise<number | null> {
  const start = formatDate(new Date(Date.now() - days * 24 * 60 * 60 * 1000))
  const rows = await db
    .select({
      occurredAt: transactions.occurredAt,
      amount: transactions.amount,
    })
    .from(transactions)
    .innerJoin(accounts, eq(transactions.accountId, accounts.id))
    .where(
      and(
        isNull(transactions.deletedAt),
        gte(transactions.occurredAt, start),
        sql`${transactions.transferPairId} IS NULL`,
        eq(accounts.isArchived, false),
      ),
    )
    .orderBy(asc(transactions.occurredAt))

  const inflows: { date: Date; remaining: number }[] = []
  const matches: { spendDate: Date; inflowDate: Date; amount: number }[] = []
  for (const row of rows) {
    const amount = Number(row.amount)
    const date = new Date(row.occurredAt)
    if (amount > 0) {
      inflows.push({ date, remaining: amount })
    } else if (amount < 0) {
      let needed = Math.abs(amount)
      while (needed > 0 && inflows.length > 0) {
        const head = inflows[0]
        if (!head) break
        const take = Math.min(head.remaining, needed)
        matches.push({ spendDate: date, inflowDate: head.date, amount: take })
        head.remaining -= take
        needed -= take
        if (head.remaining <= 0.01) inflows.shift()
      }
    }
  }
  if (matches.length === 0) return null
  const totalAmount = matches.reduce((s, m) => s + m.amount, 0)
  if (totalAmount === 0) return null
  const weighted = matches.reduce((s, m) => {
    const ageDays = (m.spendDate.getTime() - m.inflowDate.getTime()) / 86400000
    return s + ageDays * m.amount
  }, 0)
  return weighted / totalAmount
}

export async function getNetWorthSeries(db: SqliteDB, months = 24): Promise<NetWorthPoint[]> {
  const { net: currentNet } = await getNetWorth(db)

  const rows = await db
    .select({
      month: sql<string>`strftime('%Y-%m', ${transactions.occurredAt})`,
      total: sql<number>`COALESCE(SUM(${transactions.amount}), 0)`,
    })
    .from(transactions)
    .innerJoin(accounts, eq(transactions.accountId, accounts.id))
    .where(
      and(
        isNull(transactions.deletedAt),
        sql`${transactions.transferPairId} IS NULL`,
        eq(accounts.isArchived, false),
        sql`${accounts.kind} <> 'loan'`,
      ),
    )
    .groupBy(sql`strftime('%Y-%m', ${transactions.occurredAt})`)

  const byMonth = new Map<string, number>()
  for (const r of rows) {
    byMonth.set(r.month, Number(r.total))
  }

  const out: NetWorthPoint[] = []
  let bal = currentNet
  for (let i = 0; i < months; i++) {
    const d = addMonths(new Date(), -i)
    const key = `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`
    out.push({ month: key, cumulative: bal })
    bal -= byMonth.get(key) ?? 0
  }
  return out.reverse()
}

// ============ date helpers ============
function startOfMonth(d: Date): Date {
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1))
}

function addMonths(d: Date, n: number): Date {
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + n, d.getUTCDate()))
}

function formatDate(d: Date): string {
  return d.toISOString().slice(0, 10)
}
