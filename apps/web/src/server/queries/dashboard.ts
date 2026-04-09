import { and, desc, eq, gte, isNull, lte, sql } from 'drizzle-orm'
import { db } from '@/db/client'
import { accounts, categories, categoryGroups, transactions } from '@/db/schema'
import { getLoanLiabilities } from './loan-liabilities'

export interface NetWorth {
  /** Gross = sum of non-loan included accounts' current_balance (assets
   * only). Mirrors PATRIMOINE BRUT in the legacy sheet. */
  gross: number
  /** Total liability = Σ amortization-based remaining debt across every
   * loan-kind included account. Positive number. */
  liability: number
  /** Net = gross − liability. Mirrors PATRIMOINE NET in the legacy sheet. */
  net: number
}

/**
 * Net worth is computed live from the `accounts` table + amortization math
 * for any loan accounts:
 *
 *   gross     = Σ(account.current_balance) for non-loan included accounts
 *   liability = Σ amortization-derived restant dû for each included loan
 *   net       = gross − liability
 *
 * We deliberately do NOT use `balance_snapshots` for the headline number —
 * the snapshot is just a point-in-time copy and gets stale the moment a
 * balance changes. The accounts table is the source of truth for assets;
 * the amortization schedule (driven by loan params: principal, rate, term,
 * start date, mensualité) is the source of truth for liabilities.
 *
 * Why not just read `account.current_balance` for loans? Because for a loan
 * it's the running sum of the payment-mirror rows we insert on the loan
 * account (one +135,91 € row per mensualité) — which drifts away from the
 * bank's real capital restant dû by the amount of interest already paid.
 * On a 10 000 € / 3.9 % / 84 months loan after 22 payments the naive number
 * understates the liability by ~635 €, which was flipping net worth the
 * wrong way (net > gross!) instead of pulling it down.
 */
export async function getNetWorth(): Promise<NetWorth> {
  const accountRows = await db.query.accounts.findMany({
    where: eq(accounts.isIncludedInNetWorth, true),
  })
  const liabilityMap = await getLoanLiabilities(accountRows)

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

export interface BurnOptions {
  fixedOnly?: boolean
}

/**
 * Burn-side amount expression: negative spend counts as burn, positive
 * refunds on expense categories net against it, and income-kind rows (salary)
 * are excluded entirely so a payday doesn't "cancel" the metric.
 *
 *   amount < 0 AND kind != 'income'         → counted as-is (outflow)
 *   amount > 0 AND kind  = 'expense'        → counted as-is (refund, reduces burn)
 *   anything else                           → ignored
 *
 * The fix here is the refund branch. The previous query hard-filtered
 * `amount < 0`, so a 50 € return on a 50 € purchase left the burn at 50
 * instead of 0, which made the KPI read ~20 % high some months. Uncategorized
 * negatives still count (conservative: treat unknown spend as spend);
 * uncategorized positives still do not (we can't prove they're refunds).
 */
const burnAmountSql = sql<string>`COALESCE(SUM(CASE
  WHEN ${transactions.amount} < 0 AND (${categoryGroups.kind} IS NULL OR ${categoryGroups.kind} <> 'income') THEN ${transactions.amount}
  WHEN ${transactions.amount} > 0 AND ${categoryGroups.kind} = 'expense' THEN ${transactions.amount}
  ELSE 0
END), 0)`

export async function getMonthBurn(opts: BurnOptions = {}): Promise<number> {
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
  // CASE sums to a non-positive number (outflow), so |total| is the burn.
  // If refunds somehow exceed expenses (rare — big return month) we clamp
  // at 0 because a "negative burn" would mean "you earned money" which is
  // not what this KPI represents.
  const total = Number(rows[0]?.total ?? '0')
  return total >= 0 ? 0 : Math.abs(total)
}

export async function getAvgMonthlyBurn(months = 6): Promise<number> {
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

export interface PatrimonyPoint {
  date: string
  balance: number
}

/**
 * Patrimony time series — daily net worth for the last N months. Derived
 * live from (sum of current account balances minus loan liability) +
 * transactions, not from the `balance_snapshots` table. Snapshots are an
 * orphan feature: no job ever wrote to them, which is why the chart
 * rendered "No snapshots yet" forever.
 *
 * Algorithm (same spirit as `getNetWorthSeries` in reflect.ts, but daily):
 *   1. Anchor at today = getNetWorth().net so the right edge of the chart
 *      meets the headline KPI exactly.
 *   2. Walk backward day by day, subtracting each day's transaction net to
 *      get the balance at the END of the previous day. Loan accounts are
 *      excluded from the per-day walk because their mirror rows aren't a
 *      cash flow — the liability is already baked into the anchor.
 *   3. Emit a point per day so the chart's time-scale X-axis renders the
 *      curve smoothly at its actual calendar position.
 *
 * CAVEAT: treating the loan liability as constant across the window is an
 * approximation (the real restant dû drops by ~principal/month = ~126 €/
 * month on the user's 10k€ loan). Good enough for a 12-month chart; if
 * this becomes visible we'll need to recompute the schedule balance at
 * each historical date.
 */
export async function getPatrimonyTimeSeries(months = 12): Promise<PatrimonyPoint[]> {
  const today = new Date()
  const start = startOfMonth(addMonths(today, -months + 1))

  // Live anchor — identical math to getNetWorth() so the right edge of the
  // chart meets the "Net worth" KPI exactly.
  const { net: currentNet } = await getNetWorth()

  // Per-day transaction nets across the window, excluding loan accounts.
  // Loan mirrors (+135.91 €) are accounting entries, not cash movements;
  // including them would double-subtract the liability which is already
  // baked into the anchor above.
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

  // Iterate backward from today to `start`, then reverse. Using calendar
  // arithmetic (not Date.now() - i*DAY_MS) so daylight-saving shifts don't
  // drop or duplicate a day at the boundary.
  const out: PatrimonyPoint[] = []
  let bal = currentNet
  const cursor = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate()))
  const startUtc = Date.UTC(start.getUTCFullYear(), start.getUTCMonth(), start.getUTCDate())

  while (cursor.getTime() >= startUtc) {
    const iso = cursor.toISOString().slice(0, 10)
    out.push({ date: iso, balance: bal })
    // Step back one day and subtract the day we just emitted — yesterday's
    // end-of-day balance equals today's end-of-day minus today's transactions.
    bal -= netByDay.get(iso) ?? 0
    cursor.setUTCDate(cursor.getUTCDate() - 1)
  }

  return out.reverse()
}

export interface CategoryBreakdownItem {
  groupName: string
  categoryName: string
  emoji: string | null
  total: number
  color: string | null
}

export async function getMonthByCategory(): Promise<CategoryBreakdownItem[]> {
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

export interface TopExpense {
  id: string
  payee: string
  date: Date
  amount: number
  categoryName: string | null
}

/**
 * Top N expenses in the last `days` window. Defaults to 30 days — the user
 * usually wants "recent" not "this calendar month" (which is often empty
 * early in the month). Pass `categoryId` to scope the list to one category;
 * `null` (default) keeps it across all categories.
 */
export async function getTopExpenses(
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

/**
 * Count of current-month expense transactions that have no category assigned.
 * Used to differentiate "no expenses at all" vs. "expenses exist but all uncategorized"
 * in the category breakdown widget.
 */
export async function countUncategorizedExpensesThisMonth(): Promise<number> {
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

export interface DataSourceInfo {
  /** Discriminator: where the bulk of the data comes from. */
  kind: 'legacy_xlsx' | 'manual' | 'mixed' | 'empty'
  /** Most recent legacy import — falls back to most recent transaction
   * createdAt if we don't have a dedicated import-log table yet. */
  lastImportAt: Date | null
  /** True if any account is sync-linked to a real bank API. Currently always
   * false until the GoCardless BAD integration lands. */
  hasBankApi: boolean
  totalAccounts: number
  legacyAccounts: number
  manualAccounts: number
}

/**
 * Returns provenance metadata about the data shown on the dashboard. Used by
 * the "Data source" pill so the user can see at a glance whether numbers come
 * from the legacy XLSX import, manual edits, or a real bank API.
 */
export async function getDataSourceInfo(): Promise<DataSourceInfo> {
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
