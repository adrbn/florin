import { and, desc, eq, gte, isNotNull, isNull, lte, sql } from 'drizzle-orm'
import type { SqliteDB } from '../client'
import { accounts, categories, categoryGroups, transactions } from '../schema'
import { getLoanLiabilities } from './loan-liabilities'
import { detectSubscriptions } from '@florin/core/lib/transactions'

import type {
  NetWorth,
  BurnOptions,
  PatrimonyPoint,
  CategoryBreakdownItem,
  TopExpense,
  DataSourceInfo,
  LeftToSpend,
  DailySpend,
  DailyCategorySpend,
  SavingsRates,
  SubscriptionMatch,
} from '@florin/core/types'

export async function getNetWorth(db: SqliteDB): Promise<NetWorth> {
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

  const net = gross - liability
  const netMonthAgo = await computeNetMonthAgo(db, net)
  return { gross, liability, net, netMonthAgo }
}

/**
 * Walk non-loan, included-in-NW transactions backward from today to the same
 * day of the previous month. Returns null when the oldest transaction in scope
 * is newer than the target date (history too short to compare).
 */
async function computeNetMonthAgo(db: SqliteDB, currentNet: number): Promise<number | null> {
  const today = new Date()
  const target = new Date(
    Date.UTC(today.getUTCFullYear(), today.getUTCMonth() - 1, today.getUTCDate()),
  )
  const targetIso = formatDate(target)
  const todayIso = formatDate(today)

  const [oldestRow] = await db
    .select({ oldest: sql<string>`MIN(${transactions.occurredAt})` })
    .from(transactions)
    .innerJoin(accounts, eq(transactions.accountId, accounts.id))
    .where(
      and(
        isNull(transactions.deletedAt),
        sql`${transactions.transferPairId} IS NULL`,
        eq(accounts.isArchived, false),
        eq(accounts.isIncludedInNetWorth, true),
        sql`${accounts.kind} <> 'loan'`,
      ),
    )

  const oldest = oldestRow?.oldest ?? null
  if (!oldest || oldest > targetIso) {
    return null
  }

  const [sumRow] = await db
    .select({ total: sql<number>`COALESCE(SUM(${transactions.amount}), 0)` })
    .from(transactions)
    .innerJoin(accounts, eq(transactions.accountId, accounts.id))
    .where(
      and(
        isNull(transactions.deletedAt),
        sql`${transactions.transferPairId} IS NULL`,
        eq(accounts.isArchived, false),
        eq(accounts.isIncludedInNetWorth, true),
        sql`${accounts.kind} <> 'loan'`,
        sql`${transactions.occurredAt} > ${targetIso}`,
        lte(transactions.occurredAt, todayIso),
      ),
    )
  const delta = Number(sumRow?.total ?? 0)
  return currentNet - delta
}

/**
 * Burn-side amount expression: negative spend counts as burn, positive
 * refunds on expense categories net against it, and income-kind rows (salary)
 * are excluded entirely so a payday doesn't "cancel" the metric.
 */
// SEPA outgoing transfer payees ("VIREMENT POUR …", "VIREMENT VERS …")
// that the user hasn't categorized are zeroed out — they're not real
// expenses, just money moving between the user's own accounts at
// different banks. Same heuristic as getDailySpend.
const burnAmountSql = sql<number>`COALESCE(SUM(CASE
  WHEN UPPER(${transactions.payee}) LIKE 'VIREMENT %' AND ${transactions.categoryId} IS NULL THEN 0
  WHEN ${transactions.amount} < 0 AND (${categoryGroups.kind} IS NULL OR ${categoryGroups.kind} <> 'income') THEN ${transactions.amount}
  WHEN ${transactions.amount} > 0 AND ${categoryGroups.kind} = 'expense' THEN ${transactions.amount}
  ELSE 0
END), 0)`

export async function getMonthBurn(db: SqliteDB, opts: BurnOptions = {}): Promise<number> {
  const start = formatDate(startOfMonth(new Date()))
  const end = formatDate(endOfMonth(new Date()))
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
  const total = Number(rows[0]?.total ?? 0)
  return total >= 0 ? 0 : Math.abs(total)
}

export async function getAvgMonthlyBurn(db: SqliteDB, months = 6): Promise<number> {
  const end = formatDate(endOfMonth(new Date()))
  const start = formatDate(startOfMonth(addMonths(new Date(), -months + 1)))
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
  const total = Number(rows[0]?.total ?? 0)
  const burn = total >= 0 ? 0 : Math.abs(total)
  return burn / months
}

export async function getPatrimonyTimeSeries(
  db: SqliteDB,
  months = 12,
): Promise<PatrimonyPoint[]> {
  const today = new Date()
  const start = startOfMonth(addMonths(today, -months + 1))

  const { net: currentNet } = await getNetWorth(db)

  const rows = await db
    .select({
      day: sql<string>`strftime('%Y-%m-%d', ${transactions.occurredAt})`,
      total: sql<number>`COALESCE(SUM(${transactions.amount}), 0)`,
    })
    .from(transactions)
    .innerJoin(accounts, eq(transactions.accountId, accounts.id))
    .where(
      and(
        isNull(transactions.deletedAt),
        gte(transactions.occurredAt, formatDate(start)),
        sql`${transactions.transferPairId} IS NULL`,
        eq(accounts.isArchived, false),
        eq(accounts.isIncludedInNetWorth, true),
        sql`${accounts.kind} <> 'loan'`,
      ),
    )
    .groupBy(sql`strftime('%Y-%m-%d', ${transactions.occurredAt})`)

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

export async function getMonthByCategory(db: SqliteDB): Promise<CategoryBreakdownItem[]> {
  const start = formatDate(startOfMonth(new Date()))
  const end = formatDate(endOfMonth(new Date()))
  const rows = await db
    .select({
      categoryId: categories.id,
      categoryName: categories.name,
      emoji: categories.emoji,
      groupName: categoryGroups.name,
      color: categoryGroups.color,
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
      categoryId: r.categoryId,
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
  db: SqliteDB,
  n = 5,
  days = 30,
  categoryId: string | null = null,
): Promise<TopExpense[]> {
  const start = formatDate(new Date(Date.now() - days * 24 * 60 * 60 * 1000))
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
    date: new Date(r.date),
    amount: Math.abs(Number(r.amount)),
    categoryName: r.categoryName,
  }))
}

export async function countUncategorizedExpensesThisMonth(db: SqliteDB): Promise<number> {
  const start = formatDate(startOfMonth(new Date()))
  const end = formatDate(endOfMonth(new Date()))
  const rows = await db
    .select({ count: sql<number>`COUNT(*)` })
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
  return Number(rows[0]?.count ?? 0)
}

export async function getDataSourceInfo(db: SqliteDB): Promise<DataSourceInfo> {
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
    lastImportAt: latestLegacy?.createdAt ? new Date(latestLegacy.createdAt) : null,
    hasBankApi,
    totalAccounts,
    legacyAccounts,
    manualAccounts,
  }
}

/**
 * Minimum amount that counts as a salary hit when detecting the user's
 * "salary category". French SMIC net is ≈ 1450€, so anything above 500€ in
 * a single positive transaction is a safe floor that catches part-time
 * income too.
 */
const SALARY_MIN_AMOUNT = 500

/**
 * Find the category the user gets paid into by looking at the latest large
 * positive transaction (>= 500€) in the last 90 days. That category's income
 * this month becomes the "monthly ceiling"; subtract burn to get "left to
 * spend".
 */
export async function getLeftToSpendThisMonth(db: SqliteDB): Promise<LeftToSpend> {
  const lookback = formatDate(new Date(Date.now() - 90 * 24 * 60 * 60 * 1000))
  const latest = await db
    .select({ categoryId: transactions.categoryId, categoryName: categories.name })
    .from(transactions)
    .innerJoin(accounts, eq(transactions.accountId, accounts.id))
    .leftJoin(categories, eq(transactions.categoryId, categories.id))
    .where(
      and(
        isNull(transactions.deletedAt),
        isNotNull(transactions.categoryId),
        gte(transactions.occurredAt, lookback),
        sql`${transactions.amount} >= ${SALARY_MIN_AMOUNT}`,
        sql`${transactions.transferPairId} IS NULL`,
        eq(accounts.isArchived, false),
      ),
    )
    .orderBy(desc(transactions.occurredAt))
    .limit(1)

  const salaryCategoryId = latest[0]?.categoryId ?? null
  const salaryCategoryName = latest[0]?.categoryName ?? null

  const startDate = startOfMonth(new Date())

  let monthIncome = 0
  if (salaryCategoryId) {
    // Sum salary income per calendar month over the lookback window. Prefer
    // the current month; if it hasn't been paid yet (e.g. salary lands on the
    // 25th-28th), fall back to the most recent month that saw a hit.
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
          eq(transactions.categoryId, salaryCategoryId),
          gte(transactions.occurredAt, lookback),
          sql`${transactions.amount} > 0`,
          sql`${transactions.transferPairId} IS NULL`,
          eq(accounts.isArchived, false),
        ),
      )
      .groupBy(sql`strftime('%Y-%m', ${transactions.occurredAt})`)
      .orderBy(sql`strftime('%Y-%m', ${transactions.occurredAt}) DESC`)

    const currentKey = `${startDate.getFullYear()}-${String(startDate.getMonth() + 1).padStart(2, '0')}`
    const currentRow = rows.find((r) => r.month === currentKey)
    const fallbackRow = rows[0]
    monthIncome = Number((currentRow ?? fallbackRow)?.total ?? 0)
  }

  const monthSpent = await getMonthBurn(db)
  const leftToSpend = monthIncome - monthSpent

  const today = new Date()
  const daysElapsed = today.getUTCDate()
  const daysInMonth = endOfMonth(today).getUTCDate()
  const daysRemaining = Math.max(0, daysInMonth - daysElapsed)
  const dailyAvgSpent = daysElapsed > 0 ? monthSpent / daysElapsed : 0
  const dailyBudgetRemaining =
    salaryCategoryId && daysRemaining > 0 ? leftToSpend / daysRemaining : null

  return {
    salaryCategoryId,
    salaryCategoryName,
    monthIncome,
    monthSpent,
    leftToSpend,
    dailyAvgSpent,
    dailyBudgetRemaining,
    daysElapsed,
    daysRemaining,
  }
}

/**
 * Per-day spending total for the heatmap. Days with no spending are omitted;
 * the caller pads missing days so the grid stays contiguous.
 */
export async function getDailySpend(db: SqliteDB, days = 91): Promise<DailySpend[]> {
  const start = formatDate(new Date(Date.now() - days * 24 * 60 * 60 * 1000))
  const rows = await db
    .select({
      day: sql<string>`strftime('%Y-%m-%d', ${transactions.occurredAt})`,
      total: sql<number>`COALESCE(SUM(${transactions.amount}), 0)`,
    })
    .from(transactions)
    .innerJoin(accounts, eq(transactions.accountId, accounts.id))
    .leftJoin(categories, eq(transactions.categoryId, categories.id))
    .leftJoin(categoryGroups, eq(categories.groupId, categoryGroups.id))
    .where(
      and(
        isNull(transactions.deletedAt),
        gte(transactions.occurredAt, start),
        sql`${transactions.amount} < 0`,
        sql`${transactions.transferPairId} IS NULL`,
        eq(accounts.isArchived, false),
        sql`(${categoryGroups.kind} IS NULL OR ${categoryGroups.kind} <> 'income')`,
        // External SEPA outgoing transfers ("VIREMENT POUR …", "VIREMENT
        // VERS …", etc.) can't be auto-paired because the destination
        // account isn't in Florin. Treating them as expenses pollutes the
        // heatmap with what is really money the user moved between their
        // own accounts. Filter them out when uncategorized — the user can
        // override by assigning a category if the transfer truly was an
        // expense (e.g. paying a friend back).
        sql`NOT (UPPER(${transactions.payee}) LIKE 'VIREMENT %' AND ${transactions.categoryId} IS NULL)`,
      ),
    )
    .groupBy(sql`strftime('%Y-%m-%d', ${transactions.occurredAt})`)

  return rows.map((r) => ({ date: r.day, amount: Math.abs(Number(r.total)) }))
}

export async function getDailySpendByCategory(
  db: SqliteDB,
  days = 91,
): Promise<DailyCategorySpend[]> {
  const start = formatDate(new Date(Date.now() - days * 24 * 60 * 60 * 1000))
  const rows = await db
    .select({
      day: sql<string>`strftime('%Y-%m-%d', ${transactions.occurredAt})`,
      categoryId: categories.id,
      categoryName: categories.name,
      groupName: categoryGroups.name,
      total: sql<number>`COALESCE(SUM(${transactions.amount}), 0)`,
    })
    .from(transactions)
    .innerJoin(accounts, eq(transactions.accountId, accounts.id))
    .leftJoin(categories, eq(transactions.categoryId, categories.id))
    .leftJoin(categoryGroups, eq(categories.groupId, categoryGroups.id))
    .where(
      and(
        isNull(transactions.deletedAt),
        gte(transactions.occurredAt, start),
        sql`${transactions.amount} < 0`,
        sql`${transactions.transferPairId} IS NULL`,
        eq(accounts.isArchived, false),
        sql`(${categoryGroups.kind} IS NULL OR ${categoryGroups.kind} <> 'income')`,
      ),
    )
    .groupBy(
      sql`strftime('%Y-%m-%d', ${transactions.occurredAt})`,
      categories.id,
      categories.name,
      categoryGroups.name,
    )

  return rows.map((r) => ({
    date: r.day,
    categoryId: r.categoryId ?? null,
    categoryName: r.categoryName ?? null,
    groupName: r.groupName ?? null,
    amount: Math.abs(Number(r.total)),
  }))
}

/**
 * Rolling savings rates — income minus expense over 3/6/12 months, divided
 * by income. Returns null for windows with no income so the UI can render a
 * placeholder instead of a misleading -100%.
 */
export async function getSavingsRates(db: SqliteDB): Promise<SavingsRates> {
  const windows: Array<{ key: keyof SavingsRates; months: number }> = [
    { key: 'threeMonth', months: 3 },
    { key: 'sixMonth', months: 6 },
    { key: 'twelveMonth', months: 12 },
  ]
  const out: SavingsRates = { threeMonth: null, sixMonth: null, twelveMonth: null }
  for (const w of windows) {
    const start = formatDate(startOfMonth(addMonths(new Date(), -w.months + 1)))
    const end = formatDate(endOfMonth(new Date()))
    const rows = await db
      .select({
        income: sql<number>`COALESCE(SUM(CASE WHEN ${categoryGroups.kind} = 'income' THEN ${transactions.amount} ELSE 0 END), 0)`,
        expense: sql<number>`COALESCE(SUM(CASE WHEN (${categoryGroups.kind} IS NULL OR ${categoryGroups.kind} <> 'income') AND ${transactions.amount} < 0 THEN ${transactions.amount} ELSE 0 END), 0)`,
      })
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
    const income = Number(rows[0]?.income ?? 0)
    const expense = Math.abs(Number(rows[0]?.expense ?? 0))
    out[w.key] = income > 0 ? ((income - expense) / income) * 100 : null
  }
  return out
}

/**
 * Subscriptions radar — scan the last 180 days of transactions and return
 * payees that repeat at roughly the same negative amount every 28±7 or
 * 7±2 days. Each group needs at least 3 samples to count.
 */
export async function getSubscriptions(db: SqliteDB): Promise<SubscriptionMatch[]> {
  const start = formatDate(new Date(Date.now() - 180 * 24 * 60 * 60 * 1000))
  const rows = await db
    .select({
      payee: transactions.normalizedPayee,
      amount: transactions.amount,
      occurredAt: transactions.occurredAt,
      categoryName: categories.name,
    })
    .from(transactions)
    .innerJoin(accounts, eq(transactions.accountId, accounts.id))
    .leftJoin(categories, eq(transactions.categoryId, categories.id))
    .where(
      and(
        isNull(transactions.deletedAt),
        gte(transactions.occurredAt, start),
        sql`${transactions.amount} < 0`,
        sql`${transactions.transferPairId} IS NULL`,
        eq(accounts.isArchived, false),
      ),
    )
    .orderBy(transactions.occurredAt)

  return detectSubscriptions(
    rows.map((r) => ({
      payee: r.payee,
      amount: Number(r.amount),
      occurredAt: r.occurredAt,
      categoryName: r.categoryName,
    })),
  )
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

function formatDate(d: Date): string {
  return d.toISOString().slice(0, 10)
}
