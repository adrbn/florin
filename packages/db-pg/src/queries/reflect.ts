import { and, asc, eq, gte, isNull, sql } from 'drizzle-orm'
import type { PgDB } from '../client'
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
} from '@florin/core/types'

export async function getMonthlyFlows(db: PgDB, months = 12): Promise<MonthlyFlow[]> {
  const start = startOfMonth(addMonths(new Date(), -(months - 1)))
  const rows = await db
    .select({
      month: sql<string>`to_char(${transactions.occurredAt}, 'YYYY-MM')`,
      income: sql<string>`COALESCE(SUM(CASE WHEN ${transactions.amount} > 0 THEN ${transactions.amount} ELSE 0 END), 0)`,
      expense: sql<string>`COALESCE(SUM(CASE WHEN ${transactions.amount} < 0 THEN ${transactions.amount} ELSE 0 END), 0)`,
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
    .groupBy(sql`to_char(${transactions.occurredAt}, 'YYYY-MM')`)
    .orderBy(sql`to_char(${transactions.occurredAt}, 'YYYY-MM')`)

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

export async function getCategoryBreakdown(db: PgDB, days = 90): Promise<CategoryShare[]> {
  const start = new Date(Date.now() - days * 24 * 60 * 60 * 1000)
  const rows = await db
    .select({
      groupName: categoryGroups.name,
      categoryName: categories.name,
      emoji: categories.emoji,
      total: sql<string>`COALESCE(SUM(${transactions.amount}), 0)`,
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

/**
 * Load on-budget, non-transfer transactions over `lookbackDays` so the FIFO
 * simulator has enough inflow history to fund today's outflows. Excludes
 * loan accounts (tracking-style) and archived accounts — YNAB's Age of
 * Money ignores tracking accounts by design.
 */
async function loadAomTxs(db: PgDB, lookbackDays: number): Promise<AomTx[]> {
  const start = new Date(Date.now() - lookbackDays * 86400000)
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
        sql`${accounts.kind} <> 'loan'`,
      ),
    )
    .orderBy(asc(transactions.occurredAt))

  return rows.map((r) => ({ date: r.occurredAt, amount: Number(r.amount) }))
}

export async function getAgeOfMoney(db: PgDB, _days = 90): Promise<number | null> {
  const txs = await loadAomTxs(db, 365)
  return computeAgeOfMoney(txs)
}

export async function getAgeOfMoneyHistory(
  db: PgDB,
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

export async function getNetWorthSeries(db: PgDB, months = 24): Promise<NetWorthPoint[]> {
  const { net: currentNet } = await getNetWorth(db)

  const rows = await db
    .select({
      month: sql<string>`to_char(${transactions.occurredAt}, 'YYYY-MM')`,
      total: sql<string>`COALESCE(SUM(${transactions.amount}), 0)`,
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
    .groupBy(sql`to_char(${transactions.occurredAt}, 'YYYY-MM')`)

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
