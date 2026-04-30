import { and, asc, eq, gte, isNull, sql } from 'drizzle-orm'
import type { SqliteDB } from '../client'
import { accounts, categories, categoryGroups, transactions } from '../schema'
import { getNetWorth } from './dashboard'
import {
  computeAgeOfMoney,
  computeAgeOfMoneyHistory,
  type AomTx,
} from '@florin/core/lib/reflect/age-of-money'

import type {
  MonthlyFlow,
  CategoryShare,
  NetWorthPoint,
  CategorySpendingSeries,
} from '@florin/core/types'

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
        // Hide uncategorized SEPA outgoing transfers — see getDailySpend.
        sql`NOT (UPPER(${transactions.payee}) LIKE 'VIREMENT %' AND ${transactions.categoryId} IS NULL)`,
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
        // Hide uncategorized SEPA outgoing transfers — see getDailySpend.
        sql`NOT (UPPER(${transactions.payee}) LIKE 'VIREMENT %' AND ${transactions.categoryId} IS NULL)`,
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

async function loadAomTxs(db: SqliteDB, lookbackDays: number): Promise<AomTx[]> {
  const start = formatDate(new Date(Date.now() - lookbackDays * 86400000))
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
        // Hide uncategorized SEPA outgoing transfers — see getDailySpend.
        sql`NOT (UPPER(${transactions.payee}) LIKE 'VIREMENT %' AND ${transactions.categoryId} IS NULL)`,
        eq(accounts.isArchived, false),
        sql`${accounts.kind} <> 'loan'`,
      ),
    )
    .orderBy(asc(transactions.occurredAt))

  return rows.map((r) => ({ date: new Date(r.occurredAt), amount: Number(r.amount) }))
}

export async function getAgeOfMoney(db: SqliteDB, _days = 90): Promise<number | null> {
  const txs = await loadAomTxs(db, 365)
  return computeAgeOfMoney(txs)
}

export async function getAgeOfMoneyHistory(
  db: SqliteDB,
  months = 12,
): Promise<{ month: string; age: number | null }[]> {
  const txs = await loadAomTxs(db, 365 * 2)
  const keys: string[] = []
  for (let i = months - 1; i >= 0; i--) {
    const d = addMonths(new Date(), -i)
    keys.push(
      `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`,
    )
  }
  return computeAgeOfMoneyHistory(txs, keys)
}

/**
 * Pivots expense transactions by (month, category) over a rolling window so
 * the Reflect page can render one trend line per category. Same filters as
 * getCategoryBreakdown: expense-kind categories only, no transfers, no
 * archived accounts. Zero-filled per month so gaps render as "0 €" instead
 * of hiding the data point.
 */
export async function getCategorySpendingSeries(
  db: SqliteDB,
  months = 12,
): Promise<CategorySpendingSeries> {
  const start = formatDate(startOfMonth(addMonths(new Date(), -(months - 1))))
  const rows = await db
    .select({
      month: sql<string>`strftime('%Y-%m', ${transactions.occurredAt})`,
      categoryId: categories.id,
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
        // Hide uncategorized SEPA outgoing transfers — see getDailySpend.
        sql`NOT (UPPER(${transactions.payee}) LIKE 'VIREMENT %' AND ${transactions.categoryId} IS NULL)`,
        eq(categoryGroups.kind, 'expense'),
        eq(accounts.isArchived, false),
      ),
    )
    .groupBy(
      sql`strftime('%Y-%m', ${transactions.occurredAt})`,
      categories.id,
      categories.name,
      categories.emoji,
    )

  const monthKeys: string[] = []
  for (let i = months - 1; i >= 0; i--) {
    const d = addMonths(new Date(), -i)
    monthKeys.push(
      `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`,
    )
  }

  interface CatAcc {
    categoryName: string
    emoji: string | null
    monthly: Map<string, number>
  }
  const byCat = new Map<string, CatAcc>()
  for (const r of rows) {
    const amt = Math.abs(Number(r.total))
    if (amt <= 0) continue
    const existing = byCat.get(r.categoryId)
    const acc: CatAcc =
      existing ?? { categoryName: r.categoryName, emoji: r.emoji, monthly: new Map() }
    acc.monthly.set(r.month, (acc.monthly.get(r.month) ?? 0) + amt)
    if (!existing) byCat.set(r.categoryId, acc)
  }

  const out = Array.from(byCat.entries())
    .map(([categoryId, acc]) => {
      const monthly = monthKeys.map((m) => acc.monthly.get(m) ?? 0)
      const total = monthly.reduce((s, v) => s + v, 0)
      return {
        categoryId,
        categoryName: acc.categoryName,
        emoji: acc.emoji,
        monthly,
        total,
      }
    })
    .filter((c) => c.total > 0)
    .sort((a, b) => b.total - a.total)

  return { months: monthKeys, categories: out }
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
        // Hide uncategorized SEPA outgoing transfers — see getDailySpend.
        sql`NOT (UPPER(${transactions.payee}) LIKE 'VIREMENT %' AND ${transactions.categoryId} IS NULL)`,
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
