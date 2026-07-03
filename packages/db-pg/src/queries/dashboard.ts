import { and, desc, eq, gt, gte, isNull, lte, sql } from 'drizzle-orm'
import type { PgDB } from '../client'
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
export async function getNetWorthAllocation(db: PgDB): Promise<NetWorthAllocation> {
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
export async function getInvestmentSnapshot(db: PgDB): Promise<InvestmentSnapshot> {
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
    const since = new Date(Date.now() - 90 * 24 * 60 * 60 * 1000)
    const [row] = await db
      .select({ total: sql<string>`COALESCE(SUM(${transactions.amount}), 0)` })
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
    monthlyContribution = Number(row?.total ?? '0') / 3
  }
  return { investedValue, monthlyContribution }
}

/**
 * Walk non-loan, included-in-NW transactions backward from today to the same
 * day of the previous month. Returns null when the oldest transaction in scope
 * is newer than the target date (history too short to compare).
 */
async function computeNetMonthAgo(db: PgDB, currentNet: number): Promise<number | null> {
  const today = new Date()
  const target = new Date(
    Date.UTC(today.getUTCFullYear(), today.getUTCMonth() - 1, today.getUTCDate()),
  )

  const [oldestRow] = await db
    .select({ oldest: sql<Date | null>`MIN(${transactions.occurredAt})` })
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

  const oldest = oldestRow?.oldest ? new Date(oldestRow.oldest) : null
  if (!oldest || oldest.getTime() > target.getTime()) {
    return null
  }

  const [sumRow] = await db
    .select({ total: sql<string>`COALESCE(SUM(${transactions.amount}), 0)` })
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
        gt(transactions.occurredAt, target),
        lte(transactions.occurredAt, today),
        // Exclude 'adjustment' plugs (balance reconciliations, transfers from
        // untracked accounts). They move an account balance but aren't real
        // wealth change for the period — counting them made "vs last month"
        // jump by e.g. a +2000 "FONDS DE RLMT" consolidation.
        sql`(${categoryGroups.kind} IS NULL OR ${categoryGroups.kind} <> 'adjustment')`,
      ),
    )
  const delta = Number(sumRow?.total ?? '0')
  return currentNet - delta
}

/**
 * Burn-side amount expression: negative spend counts as burn, positive
 * refunds on expense categories net against it, and income-kind rows (salary)
 * are excluded entirely so a payday doesn't "cancel" the metric.
 */
const burnAmountSql = sql<string>`COALESCE(SUM(CASE
  WHEN ${isUncategorizedTransfer()} THEN 0
  WHEN ${transactions.amount} < 0 AND (${categoryGroups.kind} IS NULL OR ${categoryGroups.kind} = 'expense') THEN ${transactions.amount}
  WHEN ${transactions.amount} > 0 AND ${categoryGroups.kind} = 'expense' THEN ${transactions.amount}
  ELSE 0
END), 0)`

// Gross variant: outflows only, no positive-refund netting. See BurnOptions.gross.
const grossBurnAmountSql = sql<string>`COALESCE(SUM(CASE
  WHEN ${isUncategorizedTransfer()} THEN 0
  WHEN ${transactions.amount} < 0 AND (${categoryGroups.kind} IS NULL OR ${categoryGroups.kind} = 'expense') THEN ${transactions.amount}
  ELSE 0
END), 0)`

export async function getMonthBurn(db: PgDB, opts: BurnOptions = {}): Promise<number> {
  const start = startOfMonth(new Date())
  const end = endOfMonth(new Date())
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
        eq(transactions.status, 'cleared'),
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
    .leftJoin(categories, eq(transactions.categoryId, categories.id))
    .leftJoin(categoryGroups, eq(categories.groupId, categoryGroups.id))
    .where(
      and(
        isNull(transactions.deletedAt),
        eq(transactions.status, 'cleared'),
        gte(transactions.occurredAt, start),
        lte(transactions.occurredAt, today),
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

/**
 * Realized net worth plus the sum of not-yet-realized rows (scheduled, or
 * future-dated) within `horizonDays`. Transfer legs are excluded (they net to
 * zero across accounts). Loans/archived/excluded accounts out of scope.
 */
export async function getProjectedNetWorth(
  db: PgDB,
  horizonDays = 90,
): Promise<{ projected: number; scheduledDelta: number }> {
  const { net } = await getNetWorth(db)
  const [row] = await db
    .select({ total: sql<string>`COALESCE(SUM(${transactions.amount}), 0)` })
    .from(transactions)
    .innerJoin(accounts, eq(transactions.accountId, accounts.id))
    .where(
      and(
        isNull(transactions.deletedAt),
        sql`${transactions.transferPairId} IS NULL`,
        eq(accounts.isArchived, false),
        eq(accounts.isIncludedInNetWorth, true),
        sql`${accounts.kind} <> 'loan'`,
        sql`(${transactions.status} = 'scheduled' OR ${transactions.occurredAt}::date > CURRENT_DATE)`,
        sql`${transactions.occurredAt}::date <= CURRENT_DATE + ${horizonDays} * INTERVAL '1 day'`,
      ),
    )
  const scheduledDelta = Number(row?.total ?? '0')
  return { projected: net + scheduledDelta, scheduledDelta }
}

/**
 * Per-account sum of not-yet-realized amounts (scheduled or future-dated), so
 * the accounts UI can show "réalisé (+X prévu)". Keyed by accountId.
 */
export async function getScheduledDeltaByAccount(db: PgDB): Promise<Record<string, number>> {
  const rows = await db
    .select({
      accountId: transactions.accountId,
      total: sql<string>`COALESCE(SUM(${transactions.amount}), 0)`,
    })
    .from(transactions)
    .where(
      and(
        isNull(transactions.deletedAt),
        sql`(${transactions.status} = 'scheduled' OR ${transactions.occurredAt}::date > CURRENT_DATE)`,
      ),
    )
    .groupBy(transactions.accountId)
  const map: Record<string, number> = {}
  for (const r of rows) {
    if (r.accountId) map[r.accountId] = Number(r.total)
  }
  return map
}

export async function getMonthByCategory(db: PgDB): Promise<CategoryBreakdownItem[]> {
  const start = startOfMonth(new Date())
  const end = endOfMonth(new Date())
  const rows = await db
    .select({
      categoryId: categories.id,
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
  db: PgDB,
  n = 5,
  days = 30,
  categoryId: string | null = null,
): Promise<TopExpense[]> {
  const start = new Date(Date.now() - days * 24 * 60 * 60 * 1000)
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
    date: r.date,
    amount: Math.abs(Number(r.amount)),
    categoryName: r.categoryName,
  }))
}

/**
 * Richer "top spend" query backing the dashboard card: returns either the
 * biggest single transactions or the biggest merchants (payees aggregated),
 * each with its share of the period's total expense, plus that total so the
 * caller can render percentages without a second round-trip.
 */
export async function getTopSpend(
  db: PgDB,
  params: TopSpendParams,
): Promise<TopSpendResult> {
  const { mode, limit, days, categoryId, minAmount } = params
  const start = new Date(Date.now() - days * 24 * 60 * 60 * 1000)
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
    conds.push(sql`ABS(${transactions.amount}) >= ${minAmount.toFixed(2)}`)
  }

  const totalRows = await db
    .select({ total: sql<string>`COALESCE(SUM(ABS(${transactions.amount})), 0)` })
    .from(transactions)
    .innerJoin(accounts, eq(transactions.accountId, accounts.id))
    .where(and(...conds))
  const periodTotal = Number(totalRows[0]?.total ?? '0')
  const pct = (v: number) => (periodTotal > 0 ? (v / periodTotal) * 100 : 0)

  if (mode === 'merchants') {
    const rows = await db
      .select({
        key: transactions.normalizedPayee,
        rawPayee: sql<string>`MAX(${transactions.payee})`,
        total: sql<string>`SUM(ABS(${transactions.amount}))`,
        count: sql<string>`COUNT(*)`,
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
      date: r.date.toISOString().slice(0, 10),
      categoryName: r.categoryName,
      count: null,
    }
  })
  return { items, periodTotal }
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
        eq(transactions.status, 'cleared'),
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
 * Find the category the user gets paid into by looking at the latest large
 * positive transaction (>= 500€) in the last 90 days. That category's income
 * this month becomes the "monthly ceiling"; subtract burn to get "left to
 * spend". Returns zeros + null ids when the user hasn't been paid recently
 * (e.g. fresh Florin install).
 */
export async function getLeftToSpendThisMonth(db: PgDB): Promise<LeftToSpend> {
  const lookback = new Date(Date.now() - 90 * 24 * 60 * 60 * 1000)
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
    .orderBy(desc(transactions.occurredAt))
    .limit(1)

  const salaryCategoryId = latest[0]?.categoryId ?? null
  const salaryCategoryName = latest[0]?.categoryName ?? null

  const start = startOfMonth(new Date())

  let monthIncome = 0
  if (salaryCategoryId) {
    // Sum salary income for the current month. If this month hasn't been
    // paid yet (typical early in the month — salaries often land on the
    // 25th-28th), fall back to the most recent calendar month that did
    // see a salary hit so the "left to spend" ceiling stays meaningful.
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
          eq(transactions.status, 'cleared'),
          eq(transactions.categoryId, salaryCategoryId),
          gte(transactions.occurredAt, lookback),
          sql`${transactions.amount} > 0`,
          sql`${transactions.transferPairId} IS NULL`,
          eq(accounts.isArchived, false),
        ),
      )
      .groupBy(sql`to_char(${transactions.occurredAt}, 'YYYY-MM')`)
      .orderBy(sql`to_char(${transactions.occurredAt}, 'YYYY-MM') DESC`)

    const currentKey = `${start.getFullYear()}-${String(start.getMonth() + 1).padStart(2, '0')}`
    const currentRow = rows.find((r) => r.month === currentKey)
    const fallbackRow = rows[0]
    monthIncome = Number((currentRow ?? fallbackRow)?.total ?? '0')
  }

  // Gross so "spent so far" reads what actually went out and matches the
  // dashboard burn card + tray; a reimbursement shouldn't zero it early-month.
  const monthSpent = await getMonthBurn(db, { gross: true })
  const monthSpentFixed = await getMonthBurn(db, { fixedOnly: true })
  const expectedMonthlySpend = await getAvgMonthlyBurn(db, 6)
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
    leftToSpend,
    dailyAvgSpent,
    dailyBudgetRemaining,
    daysElapsed,
    daysRemaining,
  }
}

/**
 * Per-day spending total for the heatmap. Days with no spending return 0;
 * the caller pads missing days so the grid stays contiguous.
 */
export async function getDailySpend(db: PgDB, days = 91): Promise<DailySpend[]> {
  const start = new Date(Date.now() - days * 24 * 60 * 60 * 1000)
  const rows = await db
    .select({
      day: sql<string>`to_char(${transactions.occurredAt}, 'YYYY-MM-DD')`,
      total: sql<string>`COALESCE(SUM(${transactions.amount}), 0)`,
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
        // account isn't in Florin. Treat them as transfers, not expenses,
        // when uncategorized — the user can override by assigning a
        // category if the transfer truly was an expense.
        notUncategorizedTransfer(),
      ),
    )
    .groupBy(sql`to_char(${transactions.occurredAt}, 'YYYY-MM-DD')`)

  return rows.map((r) => ({ date: r.day, amount: Math.abs(Number(r.total)) }))
}

/**
 * Per-day spending broken down by category. Powers the heatmap's "exclude
 * category" filter (one row per (day, category) pair; uncategorised
 * expenses land in a single null-category row per day).
 */
export async function getDailySpendByCategory(
  db: PgDB,
  days = 91,
): Promise<DailyCategorySpend[]> {
  const start = new Date(Date.now() - days * 24 * 60 * 60 * 1000)
  const rows = await db
    .select({
      day: sql<string>`to_char(${transactions.occurredAt}, 'YYYY-MM-DD')`,
      categoryId: categories.id,
      categoryName: categories.name,
      groupName: categoryGroups.name,
      isFixed: categories.isFixed,
      total: sql<string>`COALESCE(SUM(${transactions.amount}), 0)`,
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
        // account isn't in Florin. Treat them as transfers, not expenses,
        // when uncategorized — the user can override by assigning a
        // category if the transfer truly was an expense.
        notUncategorizedTransfer(),
      ),
    )
    .groupBy(
      sql`to_char(${transactions.occurredAt}, 'YYYY-MM-DD')`,
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
export async function getSavingsRates(db: PgDB): Promise<SavingsRates> {
  const windows: Array<{ key: keyof SavingsRates; months: number }> = [
    { key: 'threeMonth', months: 3 },
    { key: 'sixMonth', months: 6 },
    { key: 'twelveMonth', months: 12 },
  ]
  const out: SavingsRates = { threeMonth: null, sixMonth: null, twelveMonth: null }
  for (const w of windows) {
    const start = startOfMonth(addMonths(new Date(), -w.months + 1))
    const end = endOfMonth(new Date())
    const rows = await db
      .select({
        income: sql<string>`COALESCE(SUM(CASE WHEN ${categoryGroups.kind} = 'income' THEN ${transactions.amount} ELSE 0 END), 0)`,
        // Net the CATEGORIZED expense groups (sum all amounts, not just the
        // negatives): a positive booked into an expense category — a friend
        // repaying their share of a shared bill, a merchant refund — OFFSETS
        // that category's outflow. Counting only negatives inflated expenses
        // and crushed the rate. `= 'expense'` excludes uncategorized (NULL) and
        // the 'adjustment' kind — balance-reconciliation plugs and untracked-
        // account transfers, which aren't income or spending.
        nonIncomeNet: sql<string>`COALESCE(SUM(CASE WHEN ${categoryGroups.kind} = 'expense' THEN ${transactions.amount} ELSE 0 END), 0)`,
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
    const income = Number(rows[0]?.income ?? '0')
    // nonIncomeNet is negative overall (spending net of refunds/reimbursements);
    // savings = income + nonIncomeNet = what actually stayed.
    const nonIncomeNet = Number(rows[0]?.nonIncomeNet ?? '0')
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
export async function getSubscriptions(db: PgDB): Promise<SubscriptionMatch[]> {
  const start = new Date(Date.now() - 180 * 24 * 60 * 60 * 1000)
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
      occurredAt: new Date(r.occurredAt).toISOString(),
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
