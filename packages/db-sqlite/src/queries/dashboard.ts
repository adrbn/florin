import { and, desc, eq, gte, isNull, lte, sql } from 'drizzle-orm'
import type { SqliteDB } from '../client'
import { accounts, categories, categoryGroups, recurringRules, transactions } from '../schema'
import { getLoanLiabilities } from './loan-liabilities'
import { isUncategorizedTransfer, notUncategorizedTransfer } from './transfer-filter'
import { detectSubscriptions } from '@florin/core/lib/transactions'
import { cleanDisplayName } from '@florin/core/lib/categorization'

import type {
  NetWorth,
  NetWorthAllocation,
  InvestmentSnapshot,
  BurnOptions,
  PatrimonyPoint,
  CategoryBreakdownItem,
  TopExpense,
  TopSpendParams,
  TopSpendResult,
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
    } else if (a.kind === 'broker_portfolio') {
      // Holdings market value (Σ qty × lastPrice) plus idle cash sitting in the
      // wrapper (currentBalance = realized versements not yet invested).
      gross += Number(a.marketValue) + Number(a.currentBalance)
    } else {
      gross += Number(a.currentBalance)
    }
  }

  const net = gross - liability
  const netMonthAgo = await computeNetMonthAgo(db, net)
  return { gross, liability, net, netMonthAgo }
}

/** Net worth split into cash / invested / loans for the allocation donut. */
export async function getNetWorthAllocation(db: SqliteDB): Promise<NetWorthAllocation> {
  const accountRows = await db.query.accounts.findMany({
    where: eq(accounts.isIncludedInNetWorth, true),
  })
  const liabilityMap = await getLoanLiabilities(db, accountRows)
  let cash = 0
  let invested = 0
  let loans = 0
  for (const a of accountRows) {
    if (a.kind === 'loan') {
      loans += liabilityMap.get(a.id)?.remainingDebt ?? 0
    } else if (a.kind === 'broker_portfolio' || a.kind === 'broker_cash') {
      // Idle cash inside an investment wrapper (PEA versements not yet
      // deployed) belongs to the "invested" slice — it left the day-to-day
      // cash pool the moment it entered the envelope.
      invested += Number(a.marketValue ?? 0) + Number(a.currentBalance)
    } else {
      cash += Number(a.currentBalance)
    }
  }
  return { cash, invested, loans }
}

/** Invested value + monthly DCA contribution, inputs for the goal projection. */
export async function getInvestmentSnapshot(db: SqliteDB): Promise<InvestmentSnapshot> {
  const accountRows = await db.query.accounts.findMany({
    where: eq(accounts.isIncludedInNetWorth, true),
  })
  const brokerIds = new Set<string>()
  let investedValue = 0
  for (const a of accountRows) {
    if (a.kind === 'broker_portfolio') {
      investedValue += Number(a.marketValue) + Number(a.currentBalance)
      brokerIds.add(a.id)
    } else if (a.kind === 'broker_cash') {
      investedValue += Number(a.currentBalance)
      brokerIds.add(a.id)
    }
  }
  let monthlyContribution = 0
  if (brokerIds.size > 0) {
    const rules = await db
      .select({
        amount: recurringRules.amount,
        toAccountId: recurringRules.toAccountId,
        interval: recurringRules.interval,
      })
      .from(recurringRules)
      .where(
        and(
          eq(recurringRules.isActive, true),
          eq(recurringRules.frequency, 'monthly'),
          eq(recurringRules.kind, 'transfer'),
        ),
      )
    for (const r of rules) {
      if (r.toAccountId && brokerIds.has(r.toAccountId)) {
        monthlyContribution += Number(r.amount) / Math.max(1, Number(r.interval) || 1)
      }
    }
  }
  // No explicit recurring DCA rule? Derive a rate from what actually went INTO
  // the wrapper: the trailing-3-month average of incoming transfers to broker
  // accounts. This self-corrects — each new versement lifts it, a pause lets
  // it decay — instead of showing a demoralising "0 €/mois → year 2104".
  if (monthlyContribution === 0 && brokerIds.size > 0) {
    const since = formatDate(new Date(Date.now() - 90 * 24 * 60 * 60 * 1000))
    const [row] = await db
      .select({ total: sql<number>`COALESCE(SUM(${transactions.amount}), 0)` })
      .from(transactions)
      .innerJoin(accounts, eq(transactions.accountId, accounts.id))
      .where(
        and(
          isNull(transactions.deletedAt),
          eq(transactions.status, 'cleared'),
          sql`${transactions.amount} > 0`,
          sql`${transactions.transferPairId} IS NOT NULL`,
          gte(transactions.occurredAt, since),
          sql`${accounts.kind} IN ('broker_portfolio', 'broker_cash')`,
        ),
      )
    monthlyContribution = Number(row?.total ?? 0) / 3
  }
  return { investedValue, monthlyContribution }
}

/**
 * Walk non-loan, included-in-NW transactions backward from today to the same
 * day of the previous month. Returns null when the oldest transaction in scope
 * is newer than the target date (history too short to compare).
 */
/**
 * The wealth change over the last COMPLETE calendar month.
 *
 * This used to compare today against this date last month. Arithmetically
 * sound and, on a real ledger, close to meaningless: a salary lands on a
 * drifting date — the 24th, the 26th, the 29th — so a fixed one-month window
 * catches one payday, two, or none. Measured day by day on a real account the
 * same figure read +519 on 25 July, -2 457 on the 26th, +647 on the 29th.
 * Three thousand euros of swing in four days, with nothing having happened.
 *
 * A complete calendar month contains exactly one salary, whichever day it
 * falls on. The same ledger then reads +541, +672, +442, -20, +703, +482 —
 * which is what the month actually was.
 *
 * This is the rule the savings rates already follow, and for the same reason:
 * the month in progress has its spending but not yet its income.
 *
 * Adjustment rows stay excluded — a balance reconciliation moves an account
 * without being wealth earned or spent.
 *
 * Returns null when the ledger does not reach back to that month, so the
 * dashboard says nothing rather than comparing against a month it never saw.
 */
async function computeNetMonthAgo(db: SqliteDB, currentNet: number): Promise<number | null> {
  const today = new Date()
  // The last complete month: [first day of previous month, first day of this).
  const startIso = formatDate(new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth() - 1, 1)))
  const endIso = formatDate(new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), 1)))

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
        eq(transactions.status, 'cleared'),
      ),
    )

  const oldest = oldestRow?.oldest ?? null
  if (!oldest || oldest >= endIso) {
    return null
  }

  const [sumRow] = await db
    .select({ total: sql<number>`COALESCE(SUM(${transactions.amount}), 0)` })
    .from(transactions)
    .innerJoin(accounts, eq(transactions.accountId, accounts.id))
    .leftJoin(categories, eq(transactions.categoryId, categories.id))
    .leftJoin(categoryGroups, eq(categories.groupId, categoryGroups.id))
    .where(
      and(
        isNull(transactions.deletedAt),
        sql`${transactions.transferPairId} IS NULL`,
        eq(accounts.isArchived, false),
        eq(accounts.isIncludedInNetWorth, true),
        sql`${accounts.kind} <> 'loan'`,
        eq(transactions.status, 'cleared'),
        sql`${transactions.occurredAt} >= ${startIso}`,
        sql`${transactions.occurredAt} < ${endIso}`,
        // Exclude 'adjustment' plugs (balance reconciliations, transfers from
        // untracked accounts). They move an account balance but aren't real
        // wealth change for the period — counting them made "vs last month"
        // jump by e.g. a +2000 "FONDS DE RLMT" consolidation.
        sql`(${categoryGroups.kind} IS NULL OR ${categoryGroups.kind} <> 'adjustment')`,
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
  WHEN ${isUncategorizedTransfer()} THEN 0
  WHEN ${transactions.amount} < 0 AND (${categoryGroups.kind} IS NULL OR ${categoryGroups.kind} = 'expense') THEN ${transactions.amount}
  WHEN ${transactions.amount} > 0 AND ${categoryGroups.kind} = 'expense' THEN ${transactions.amount}
  ELSE 0
END), 0)`

// Gross variant: outflows only, no positive-refund netting. See BurnOptions.gross.
const grossBurnAmountSql = sql<number>`COALESCE(SUM(CASE
  WHEN ${isUncategorizedTransfer()} THEN 0
  WHEN ${transactions.amount} < 0 AND (${categoryGroups.kind} IS NULL OR ${categoryGroups.kind} = 'expense') THEN ${transactions.amount}
  ELSE 0
END), 0)`

export async function getMonthBurn(db: SqliteDB, opts: BurnOptions = {}): Promise<number> {
  const start = formatDate(startOfMonth(new Date()))
  const end = formatDate(endOfMonth(new Date()))
  const conds = [
    isNull(transactions.deletedAt),
    eq(transactions.status, 'cleared'),
    gte(transactions.occurredAt, start),
    lte(transactions.occurredAt, end),
    sql`${transactions.transferPairId} IS NULL`,
    eq(accounts.isArchived, false),
  ]
  if (opts.fixedOnly) {
    conds.push(eq(categories.isFixed, true))
  }
  const rows = await db
    .select({ total: opts.gross ? grossBurnAmountSql : burnAmountSql })
    .from(transactions)
    .innerJoin(accounts, eq(transactions.accountId, accounts.id))
    .leftJoin(categories, eq(transactions.categoryId, categories.id))
    .leftJoin(categoryGroups, eq(categories.groupId, categoryGroups.id))
    .where(and(...conds))
  const total = Number(rows[0]?.total ?? 0)
  return total >= 0 ? 0 : Math.abs(total)
}

/**
 * Typical monthly burn, over COMPLETE months only.
 *
 * The window used to run to the end of the current month and divide by the
 * full count, so a month three days old was averaged against whole ones and
 * dragged the figure down — precisely when it is being used to stand in for a
 * partial month. The same reasoning the savings rates already follow.
 */
export async function getAvgMonthlyBurn(
  db: SqliteDB,
  months = 6,
  opts: { fixedOnly?: boolean } = {},
): Promise<number> {
  const end = formatDate(endOfMonth(addMonths(new Date(), -1)))
  const start = formatDate(startOfMonth(addMonths(new Date(), -months)))
  const rows = await db
    .select({ total: burnAmountSql })
    .from(transactions)
    .innerJoin(accounts, eq(transactions.accountId, accounts.id))
    .leftJoin(categories, eq(transactions.categoryId, categories.id))
    .leftJoin(categoryGroups, eq(categories.groupId, categoryGroups.id))
    .where(
      and(
        isNull(transactions.deletedAt),
        eq(transactions.status, 'cleared'),
        gte(transactions.occurredAt, start),
        lte(transactions.occurredAt, end),
        sql`${transactions.transferPairId} IS NULL`,
        eq(accounts.isArchived, false),
        ...(opts.fixedOnly ? [eq(categories.isFixed, true)] : []),
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
    .leftJoin(categories, eq(transactions.categoryId, categories.id))
    .leftJoin(categoryGroups, eq(categories.groupId, categoryGroups.id))
    .where(
      and(
        isNull(transactions.deletedAt),
        eq(transactions.status, 'cleared'),
        gte(transactions.occurredAt, formatDate(start)),
        lte(transactions.occurredAt, formatDate(today)),
        sql`${transactions.transferPairId} IS NULL`,
        eq(accounts.isArchived, false),
        eq(accounts.isIncludedInNetWorth, true),
        sql`${accounts.kind} <> 'loan'`,
        // Exclude 'adjustment' plugs from the historical walk. They move an
        // account balance on their booking date but don't represent wealth
        // created/lost that day (reconciliation, or a transfer in from an
        // untracked account). Including them drew a phantom vertical step —
        // e.g. a +2000 "FONDS DE RLMT" consolidation looked like a one-day
        // spike even though the real wealth curve was flat.
        sql`(${categoryGroups.kind} IS NULL OR ${categoryGroups.kind} <> 'adjustment')`,
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

/**
 * Realized net worth plus the sum of not-yet-realized rows (scheduled, or
 * future-dated) within `horizonDays`. Transfer legs are excluded (they net to
 * zero across accounts, so they don't move net worth). Loans/archived/excluded
 * accounts are out of scope, matching getNetWorth.
 */
export async function getProjectedNetWorth(
  db: SqliteDB,
  horizonDays = 90,
): Promise<{ projected: number; scheduledDelta: number }> {
  const { net } = await getNetWorth(db)
  const todayIso = formatDate(new Date())
  const horizonIso = formatDate(new Date(Date.now() + horizonDays * 86_400_000))
  const [row] = await db
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
        sql`(${transactions.status} = 'scheduled' OR ${transactions.occurredAt} > ${todayIso})`,
        lte(transactions.occurredAt, horizonIso),
      ),
    )
  const scheduledDelta = Number(row?.total ?? 0)
  return { projected: net + scheduledDelta, scheduledDelta }
}

/**
 * Per-account sum of not-yet-realized amounts (scheduled or future-dated),
 * so the accounts UI can show "réalisé (+X prévu)". Keyed by accountId.
 */
export async function getScheduledDeltaByAccount(
  db: SqliteDB,
): Promise<Record<string, number>> {
  const todayIso = formatDate(new Date())
  const rows = await db
    .select({
      accountId: transactions.accountId,
      total: sql<number>`COALESCE(SUM(${transactions.amount}), 0)`,
    })
    .from(transactions)
    .where(
      and(
        isNull(transactions.deletedAt),
        sql`(${transactions.status} = 'scheduled' OR ${transactions.occurredAt} > ${todayIso})`,
      ),
    )
    .groupBy(transactions.accountId)
  const map: Record<string, number> = {}
  for (const r of rows) {
    if (r.accountId) map[r.accountId] = Number(r.total)
  }
  return map
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
        eq(transactions.status, 'cleared'),
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
    eq(transactions.status, 'cleared'),
    gte(transactions.occurredAt, start),
    sql`${transactions.amount} < 0`,
    sql`${transactions.transferPairId} IS NULL`,
    eq(accounts.isArchived, false),
    // Exclude 'adjustment'-kind rows (e.g. cash→shares buys inside a broker
    // wrapper) — they aren't spending and must not top the expense card.
    sql`(${transactions.categoryId} IS NULL OR ${transactions.categoryId} NOT IN (
      SELECT c.id FROM categories c JOIN category_groups cg ON cg.id = c.group_id
      WHERE cg.kind = 'adjustment'))`,
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

/**
 * Richer "top spend" query backing the dashboard card: biggest single
 * transactions or biggest merchants (payees aggregated), each with its share
 * of the period's total expense, plus that total for the percentages.
 */
export async function getTopSpend(
  db: SqliteDB,
  params: TopSpendParams,
): Promise<TopSpendResult> {
  const { mode, limit, days, categoryId, minAmount } = params
  const start = formatDate(new Date(Date.now() - days * 24 * 60 * 60 * 1000))
  const conds = [
    isNull(transactions.deletedAt),
    eq(transactions.status, 'cleared'),
    gte(transactions.occurredAt, start),
    sql`${transactions.amount} < 0`,
    sql`${transactions.transferPairId} IS NULL`,
    eq(accounts.isArchived, false),
    // Exclude 'adjustment'-kind rows (e.g. cash→shares buys inside a broker
    // wrapper) — they aren't spending and must not top the expense card.
    sql`(${transactions.categoryId} IS NULL OR ${transactions.categoryId} NOT IN (
      SELECT c.id FROM categories c JOIN category_groups cg ON cg.id = c.group_id
      WHERE cg.kind = 'adjustment'))`,
  ]
  if (categoryId === 'none') {
    conds.push(isNull(transactions.categoryId))
  } else if (categoryId) {
    conds.push(eq(transactions.categoryId, categoryId))
  }
  if (minAmount > 0) {
    conds.push(sql`ABS(${transactions.amount}) >= ${minAmount}`)
  }

  const totalRows = await db
    .select({ total: sql<number>`COALESCE(SUM(ABS(${transactions.amount})), 0)` })
    .from(transactions)
    .innerJoin(accounts, eq(transactions.accountId, accounts.id))
    .where(and(...conds))
  const periodTotal = Number(totalRows[0]?.total ?? 0)
  const pct = (v: number) => (periodTotal > 0 ? (v / periodTotal) * 100 : 0)

  if (mode === 'merchants') {
    const rows = await db
      .select({
        key: transactions.normalizedPayee,
        rawPayee: sql<string>`MAX(${transactions.payee})`,
        total: sql<number>`SUM(ABS(${transactions.amount}))`,
        count: sql<number>`COUNT(*)`,
      })
      .from(transactions)
      .innerJoin(accounts, eq(transactions.accountId, accounts.id))
      .where(and(...conds))
      .groupBy(transactions.normalizedPayee)
      .orderBy(desc(sql`SUM(ABS(${transactions.amount}))`))
      .limit(limit)
    const items = rows.map((r, i) => {
      const total = Number(r.total)
      return {
        id: r.key ?? `merchant-${i}`,
        label: cleanDisplayName(r.rawPayee ?? r.key) || (r.key ?? '(unknown)'),
        amount: total,
        pctOfPeriod: pct(total),
        date: null,
        categoryName: null,
        count: Number(r.count),
      }
    })
    return { items, periodTotal }
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
    .limit(limit)
  const items = rows.map((r) => {
    const amount = Math.abs(Number(r.amount))
    return {
      id: r.id,
      label: r.payee,
      amount,
      pctOfPeriod: pct(amount),
      date: String(r.date).slice(0, 10),
      categoryName: r.categoryName,
      count: null,
    }
  })
  return { items, periodTotal }
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
        eq(transactions.status, 'cleared'),
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
 * "salary category". This is a CURRENCY-AGNOSTIC absolute floor (no FX
 * conversion happens), calibrated for currencies whose units are of
 * EUR/USD/GBP magnitude — e.g. French SMIC net is ≈ 1450€, so anything
 * above 500 in a single positive transaction is a safe floor that catches
 * part-time income too. For currencies with very different denominations
 * (e.g. JPY, where a salary is in the hundreds of thousands) this value may
 * need adjusting.
 */
const SALARY_MIN_AMOUNT = 500

/**
 * Find the category the user gets paid into, among income categories that saw
 * a large positive transaction (>= 500€) in the last 90 days. That category's
 * income this month becomes the "monthly ceiling"; subtract burn to get "left
 * to spend".
 *
 * Candidates are ranked by RECURRENCE, not recency. A salary lands in the same
 * category every single month; a one-off inflow — a cheque paid in, a tax
 * refund, a friend repaying a big shared holiday booking — lands once. Ranking
 * on "most recent single transaction" let any such one-off hijack the salary
 * category: a 500€ cheque booked to "Gains additionnels" outranked a 2 998,98€
 * monthly salary, dropping the ceiling to that category's few hundred euros
 * and turning both the monthly margin and the month forecast deeply negative
 * overnight. Distinct months with a hit is the discriminator; total is the
 * tie-break for someone with a single month of history.
 */
export async function getLeftToSpendThisMonth(db: SqliteDB): Promise<LeftToSpend> {
  const lookback = formatDate(new Date(Date.now() - 90 * 24 * 60 * 60 * 1000))
  const monthKey = sql`strftime('%Y-%m', ${transactions.occurredAt})`
  const latest = await db
    .select({ categoryId: transactions.categoryId, categoryName: categories.name })
    .from(transactions)
    .innerJoin(accounts, eq(transactions.accountId, accounts.id))
    .innerJoin(categories, eq(transactions.categoryId, categories.id))
    .innerJoin(categoryGroups, eq(categories.groupId, categoryGroups.id))
    .where(
      and(
        isNull(transactions.deletedAt),
        eq(transactions.status, 'cleared'),
        gte(transactions.occurredAt, lookback),
        sql`${transactions.amount} >= ${SALARY_MIN_AMOUNT}`,
        sql`${transactions.transferPairId} IS NULL`,
        eq(accounts.isArchived, false),
        // Only income-kind categories qualify as "salary". Without this, a
        // large inbound transfer categorized as an adjustment (e.g. topping
        // up the checking account from an untracked savings account) would
        // become the salary category and fake the whole month's margin.
        eq(categoryGroups.kind, 'income'),
      ),
    )
    .groupBy(transactions.categoryId, categories.name)
    .orderBy(
      sql`COUNT(DISTINCT ${monthKey}) DESC`,
      sql`COALESCE(SUM(${transactions.amount}), 0) DESC`,
      sql`MAX(${transactions.occurredAt}) DESC`,
    )
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
          eq(transactions.status, 'cleared'),
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

  // Gross so "spent so far" reads what actually went out and matches the
  // dashboard burn card + tray; a reimbursement shouldn't zero it early-month.
  const monthSpent = await getMonthBurn(db, { gross: true })
  const monthSpentFixed = await getMonthBurn(db, { fixedOnly: true })
  const expectedMonthlySpend = await getAvgMonthlyBurn(db, 6)
  const expectedMonthlyFixed = await getAvgMonthlyBurn(db, 6, { fixedOnly: true })
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
    monthSpentFixed,
    expectedMonthlySpend,
    expectedMonthlyFixed,
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
        eq(transactions.status, 'cleared'),
        gte(transactions.occurredAt, start),
        sql`${transactions.amount} < 0`,
        sql`${transactions.transferPairId} IS NULL`,
        eq(accounts.isArchived, false),
        sql`(${categoryGroups.kind} IS NULL OR ${categoryGroups.kind} = 'expense')`,
        // External SEPA outgoing transfers ("VIREMENT POUR …", "VIREMENT
        // VERS …", etc.) can't be auto-paired because the destination
        // account isn't in Florin. Treating them as expenses pollutes the
        // heatmap with what is really money the user moved between their
        // own accounts. Filter them out when uncategorized — the user can
        // override by assigning a category if the transfer truly was an
        // expense (e.g. paying a friend back).
        notUncategorizedTransfer(),
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
      isFixed: categories.isFixed,
      total: sql<number>`COALESCE(SUM(${transactions.amount}), 0)`,
    })
    .from(transactions)
    .innerJoin(accounts, eq(transactions.accountId, accounts.id))
    .leftJoin(categories, eq(transactions.categoryId, categories.id))
    .leftJoin(categoryGroups, eq(categories.groupId, categoryGroups.id))
    .where(
      and(
        isNull(transactions.deletedAt),
        eq(transactions.status, 'cleared'),
        gte(transactions.occurredAt, start),
        sql`${transactions.amount} < 0`,
        sql`${transactions.transferPairId} IS NULL`,
        eq(accounts.isArchived, false),
        sql`(${categoryGroups.kind} IS NULL OR ${categoryGroups.kind} = 'expense')`,
      ),
    )
    .groupBy(
      sql`strftime('%Y-%m-%d', ${transactions.occurredAt})`,
      categories.id,
      categories.name,
      categoryGroups.name,
      categories.isFixed,
    )

  return rows.map((r) => ({
    date: r.day,
    categoryId: r.categoryId ?? null,
    categoryName: r.categoryName ?? null,
    groupName: r.groupName ?? null,
    isFixed: r.isFixed ?? false,
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
    // COMPLETE calendar months only — the current month is still in progress
    // and skews the ratio hard in whichever direction the user's payday falls:
    // its spending is already booked while a salary paid on the 25th-28th is
    // not. Mid-August that read −3% over 3 months against +6% / +17% over 6
    // and 12, where the same broken month is diluted. Same reason
    // `computeCategoryMovers` compares settled months only.
    const start = formatDate(startOfMonth(addMonths(new Date(), -w.months)))
    const end = formatDate(endOfMonth(addMonths(new Date(), -1)))
    const rows = await db
      .select({
        income: sql<number>`COALESCE(SUM(CASE WHEN ${categoryGroups.kind} = 'income' THEN ${transactions.amount} ELSE 0 END), 0)`,
        // Net the CATEGORIZED expense groups (sum all amounts, not just the
        // negatives): a positive in an expense category (a friend's share
        // repaid, a refund) offsets that category's outflow. `= 'expense'`
        // excludes uncategorized (NULL) and the 'adjustment' kind — balance-
        // reconciliation plugs and untracked-account transfers.
        nonIncomeNet: sql<number>`COALESCE(SUM(CASE WHEN ${categoryGroups.kind} = 'expense' THEN ${transactions.amount} ELSE 0 END), 0)`,
      })
      .from(transactions)
      .innerJoin(accounts, eq(transactions.accountId, accounts.id))
      .leftJoin(categories, eq(transactions.categoryId, categories.id))
      .leftJoin(categoryGroups, eq(categories.groupId, categoryGroups.id))
      .where(
        and(
          isNull(transactions.deletedAt),
          eq(transactions.status, 'cleared'),
          gte(transactions.occurredAt, start),
          lte(transactions.occurredAt, end),
          sql`${transactions.transferPairId} IS NULL`,
          eq(accounts.isArchived, false),
        ),
      )
    const income = Number(rows[0]?.income ?? 0)
    // nonIncomeNet is negative overall (spending net of refunds); savings =
    // income + nonIncomeNet = what actually stayed.
    const nonIncomeNet = Number(rows[0]?.nonIncomeNet ?? 0)
    const savings = income + nonIncomeNet
    out[w.key] = income > 0 ? (savings / income) * 100 : null
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
      displayPayee: transactions.payee,
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
        eq(transactions.status, 'cleared'),
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
      displayPayee: r.displayPayee,
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
