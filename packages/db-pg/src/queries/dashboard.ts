import { and, desc, eq, gte, isNull, lte, sql } from 'drizzle-orm'
import type { PgDB } from '../client'
import { accounts, categories, categoryGroups, transactions } from '../schema'
import { getLoanLiabilities } from './loan-liabilities'

import type {
  NetWorth,
  BurnOptions,
  PatrimonyPoint,
  CategoryBreakdownItem,
  TopExpense,
  DataSourceInfo,
} from '@florin/core/types'

export async function getNetWorth(db: PgDB): Promise<NetWorth> {
  const accountRows = await db.query.accounts.findMany({
    where: eq(accounts.isIncludedInNetWorth, true),
  })
  const liabilityMap = await getLoanLiabilities(db, accountRows)

  let gross = 0
  let liability = 0
  for (const a of accountRows) {
    if (a.kind === 'loan') {
      liability += liabilityMap.get(a.id)?.remainingDebt ?? 0
    } else {
      gross += Number(a.currentBalance)
    }
  }

  return { gross, liability, net: gross - liability }
}

/**
 * Burn-side amount expression: negative spend counts as burn, positive
 * refunds on expense categories net against it, and income-kind rows (salary)
 * are excluded entirely so a payday doesn't "cancel" the metric.
 */
const burnAmountSql = sql<string>`COALESCE(SUM(CASE
  WHEN ${transactions.amount} < 0 AND (${categoryGroups.kind} IS NULL OR ${categoryGroups.kind} <> 'income') THEN ${transactions.amount}
  WHEN ${transactions.amount} > 0 AND ${categoryGroups.kind} = 'expense' THEN ${transactions.amount}
  ELSE 0
END), 0)`

export async function getMonthBurn(db: PgDB, opts: BurnOptions = {}): Promise<number> {
  const start = startOfMonth(new Date())
  const end = endOfMonth(new Date())
  const conds = [
    isNull(transactions.deletedAt),
    gte(transactions.occurredAt, start),
    lte(transactions.occurredAt, end),
    sql`${transactions.transferPairId} IS NULL`,
    eq(accounts.isArchived, false),
  ]
  if (opts.fixedOnly) {
    conds.push(eq(categories.isFixed, true))
  }
  const rows = await db
    .select({ total: burnAmountSql })
    .from(transactions)
    .innerJoin(accounts, eq(transactions.accountId, accounts.id))
    .leftJoin(categories, eq(transactions.categoryId, categories.id))
    .leftJoin(categoryGroups, eq(categories.groupId, categoryGroups.id))
    .where(and(...conds))
  const total = Number(rows[0]?.total ?? '0')
  return total >= 0 ? 0 : Math.abs(total)
}

export async function getAvgMonthlyBurn(db: PgDB, months = 6): Promise<number> {
  const end = endOfMonth(new Date())
  const start = startOfMonth(addMonths(new Date(), -months + 1))
  const rows = await db
    .select({ total: burnAmountSql })
    .from(transactions)
    .innerJoin(accounts, eq(transactions.accountId, accounts.id))
    .leftJoin(categories, eq(transactions.categoryId, categories.id))
    .leftJoin(categoryGroups, eq(categories.groupId, categoryGroups.id))
    .where(
      and(
        isNull(transactions.deletedAt),
        gte(transactions.occurredAt, start),
        lte(transactions.occurredAt, end),
        sql`${transactions.transferPairId} IS NULL`,
        eq(accounts.isArchived, false),
      ),
    )
  const total = Number(rows[0]?.total ?? '0')
  const burn = total >= 0 ? 0 : Math.abs(total)
  return burn / months
}

export async function getPatrimonyTimeSeries(db: PgDB, months = 12): Promise<PatrimonyPoint[]> {
  const today = new Date()
  const start = startOfMonth(addMonths(today, -months + 1))

  const { net: currentNet } = await getNetWorth(db)

  const rows = await db
    .select({
      day: sql<string>`to_char(${transactions.occurredAt}, 'YYYY-MM-DD')`,
      total: sql<string>`COALESCE(SUM(${transactions.amount}), 0)`,
    })
    .from(transactions)
    .innerJoin(accounts, eq(transactions.accountId, accounts.id))
    .where(
      and(
        isNull(transactions.deletedAt),
        gte(transactions.occurredAt, start),
        sql`${transactions.transferPairId} IS NULL`,
        eq(accounts.isArchived, false),
        eq(accounts.isIncludedInNetWorth, true),
        sql`${accounts.kind} <> 'loan'`,
      ),
    )
    .groupBy(sql`to_char(${transactions.occurredAt}, 'YYYY-MM-DD')`)

  const netByDay = new Map<string, number>()
  for (const r of rows) {
    netByDay.set(r.day, Number(r.total))
  }

  const out: PatrimonyPoint[] = []
  let bal = currentNet
  const cursor = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate()))
  const startUtc = Date.UTC(start.getUTCFullYear(), start.getUTCMonth(), start.getUTCDate())

  while (cursor.getTime() >= startUtc) {
    const iso = cursor.toISOString().slice(0, 10)
    out.push({ date: iso, balance: bal })
    bal -= netByDay.get(iso) ?? 0
    cursor.setUTCDate(cursor.getUTCDate() - 1)
  }

  return out.reverse()
}

export async function getMonthByCategory(db: PgDB): Promise<CategoryBreakdownItem[]> {
  const start = startOfMonth(new Date())
  const end = endOfMonth(new Date())
  const rows = await db
    .select({
      categoryName: categories.name,
      emoji: categories.emoji,
      groupName: categoryGroups.name,
      color: categoryGroups.color,
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
        lte(transactions.occurredAt, end),
        sql`${transactions.amount} < 0`,
        sql`${transactions.transferPairId} IS NULL`,
        eq(categoryGroups.kind, 'expense'),
        eq(accounts.isArchived, false),
      ),
    )
    .groupBy(
      categories.id,
      categories.name,
      categories.emoji,
      categoryGroups.id,
      categoryGroups.name,
      categoryGroups.color,
    )

  return rows
    .map((r) => ({
      groupName: r.groupName,
      categoryName: r.categoryName,
      emoji: r.emoji,
      color: r.color,
      total: Math.abs(Number(r.total)),
    }))
    .filter((r) => r.total > 0)
    .sort((a, b) => b.total - a.total)
}

export async function getTopExpenses(
  db: PgDB,
  n = 5,
  days = 30,
  categoryId: string | null = null,
): Promise<TopExpense[]> {
  const start = new Date(Date.now() - days * 24 * 60 * 60 * 1000)
  const conds = [
    isNull(transactions.deletedAt),
    gte(transactions.occurredAt, start),
    sql`${transactions.amount} < 0`,
    sql`${transactions.transferPairId} IS NULL`,
    eq(accounts.isArchived, false),
  ]
  if (categoryId) {
    conds.push(eq(transactions.categoryId, categoryId))
  }
  const rows = await db
    .select({
      id: transactions.id,
      payee: transactions.payee,
      date: transactions.occurredAt,
      amount: transactions.amount,
      categoryName: categories.name,
    })
    .from(transactions)
    .innerJoin(accounts, eq(transactions.accountId, accounts.id))
    .leftJoin(categories, eq(transactions.categoryId, categories.id))
    .where(and(...conds))
    .orderBy(transactions.amount)
    .limit(n)

  return rows.map((r) => ({
    id: r.id,
    payee: r.payee,
    date: r.date,
    amount: Math.abs(Number(r.amount)),
    categoryName: r.categoryName,
  }))
}

export async function countUncategorizedExpensesThisMonth(db: PgDB): Promise<number> {
  const start = startOfMonth(new Date())
  const end = endOfMonth(new Date())
  const rows = await db
    .select({ count: sql<string>`COUNT(*)` })
    .from(transactions)
    .innerJoin(accounts, eq(transactions.accountId, accounts.id))
    .where(
      and(
        isNull(transactions.deletedAt),
        isNull(transactions.categoryId),
        gte(transactions.occurredAt, start),
        lte(transactions.occurredAt, end),
        sql`${transactions.amount} < 0`,
        sql`${transactions.transferPairId} IS NULL`,
        eq(accounts.isArchived, false),
      ),
    )
  return Number(rows[0]?.count ?? '0')
}

export async function getDataSourceInfo(db: PgDB): Promise<DataSourceInfo> {
  const accountRows = await db.select({ syncProvider: accounts.syncProvider }).from(accounts)
  const totalAccounts = accountRows.length
  const legacyAccounts = accountRows.filter((a) => a.syncProvider === 'legacy').length
  const manualAccounts = accountRows.filter((a) => a.syncProvider === 'manual').length
  const hasBankApi = accountRows.some(
    (a) => a.syncProvider !== 'legacy' && a.syncProvider !== 'manual' && a.syncProvider !== null,
  )

  const [latestLegacy] = await db
    .select({ createdAt: transactions.createdAt })
    .from(transactions)
    .where(eq(transactions.source, 'legacy_xlsx'))
    .orderBy(desc(transactions.createdAt))
    .limit(1)

  const kind: DataSourceInfo['kind'] =
    totalAccounts === 0
      ? 'empty'
      : legacyAccounts > 0 && manualAccounts > 0
        ? 'mixed'
        : legacyAccounts > 0
          ? 'legacy_xlsx'
          : 'manual'

  return {
    kind,
    lastImportAt: latestLegacy?.createdAt ?? null,
    hasBankApi,
    totalAccounts,
    legacyAccounts,
    manualAccounts,
  }
}

// ============ date helpers ============
function startOfMonth(d: Date): Date {
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1))
}

function endOfMonth(d: Date): Date {
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 0, 23, 59, 59))
}

function addMonths(d: Date, n: number): Date {
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + n, d.getUTCDate()))
}
