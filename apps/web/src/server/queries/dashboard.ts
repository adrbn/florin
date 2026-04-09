import { and, desc, eq, gte, isNull, lte, sql } from 'drizzle-orm'
import { db } from '@/db/client'
import { accounts, categories, categoryGroups, transactions } from '@/db/schema'

export interface NetWorth {
  /** Net = sum of every included account's current_balance (loans pull this
   * down because their balance is negative). Mirrors PATRIMOINE NET in the
   * legacy sheet. */
  net: number
  /** Gross = sum of non-loan included accounts' current_balance. Mirrors
   * PATRIMOINE BRUT in the legacy sheet. */
  gross: number
}

/**
 * Net worth is computed live from the `accounts` table. This is the same math
 * as the legacy sheet's PATRIMOINE NET / PATRIMOINE BRUT cells:
 *   net   = Σ(account.current_balance) for every account included in net worth
 *   gross = same, excluding loan-kind accounts
 *
 * We deliberately do NOT use `balance_snapshots` for the headline number — the
 * snapshot is just a point-in-time copy and gets stale the moment a balance
 * changes. The accounts table is the source of truth; the user can edit
 * balances directly via the Accounts page when reality drifts.
 */
export async function getNetWorth(): Promise<NetWorth> {
  const accountRows = await db.query.accounts.findMany({
    where: eq(accounts.isIncludedInNetWorth, true),
  })
  let net = 0
  let gross = 0
  for (const a of accountRows) {
    const balance = Number(a.currentBalance)
    net += balance
    if (a.kind !== 'loan') {
      gross += balance
    }
  }
  return { net, gross }
}

export interface BurnOptions {
  fixedOnly?: boolean
}

export async function getMonthBurn(opts: BurnOptions = {}): Promise<number> {
  const start = startOfMonth(new Date())
  const end = endOfMonth(new Date())
  const conds = [
    isNull(transactions.deletedAt),
    gte(transactions.occurredAt, start),
    lte(transactions.occurredAt, end),
    sql`${transactions.amount} < 0`,
    sql`${transactions.transferPairId} IS NULL`,
    eq(accounts.isArchived, false),
  ]
  if (opts.fixedOnly) {
    conds.push(eq(categories.isFixed, true))
  }
  const rows = await db
    .select({
      total: sql<string>`COALESCE(SUM(${transactions.amount}), 0)`,
    })
    .from(transactions)
    .innerJoin(accounts, eq(transactions.accountId, accounts.id))
    .leftJoin(categories, eq(transactions.categoryId, categories.id))
    .where(and(...conds))
  return Math.abs(Number(rows[0]?.total ?? '0'))
}

export async function getAvgMonthlyBurn(months = 6): Promise<number> {
  const end = endOfMonth(new Date())
  const start = startOfMonth(addMonths(new Date(), -months + 1))
  const rows = await db
    .select({
      total: sql<string>`COALESCE(SUM(${transactions.amount}), 0)`,
    })
    .from(transactions)
    .innerJoin(accounts, eq(transactions.accountId, accounts.id))
    .where(
      and(
        isNull(transactions.deletedAt),
        gte(transactions.occurredAt, start),
        lte(transactions.occurredAt, end),
        sql`${transactions.amount} < 0`,
        sql`${transactions.transferPairId} IS NULL`,
        eq(accounts.isArchived, false),
      ),
    )
  const total = Math.abs(Number(rows[0]?.total ?? '0'))
  return total / months
}

export interface PatrimonyPoint {
  date: string
  balance: number
}

/**
 * Patrimony time series — daily net worth for the last N months. Derived
 * live from (sum of current account balances) + transactions, not from the
 * `balance_snapshots` table. Snapshots are an orphan feature: no job ever
 * wrote to them, which is why the chart rendered "No snapshots yet" forever.
 *
 * Algorithm (same spirit as `getNetWorthSeries` in reflect.ts, but daily):
 *   1. Anchor at today = sum of current_balance for net-worth-included,
 *      non-archived accounts. This matches the headline KPI.
 *   2. Walk backward day by day, subtracting each day's transaction net to
 *      get the balance at the END of the previous day.
 *   3. Emit a point per day so the chart's time-scale X-axis renders the
 *      curve smoothly at its actual calendar position.
 */
export async function getPatrimonyTimeSeries(months = 12): Promise<PatrimonyPoint[]> {
  const today = new Date()
  const start = startOfMonth(addMonths(today, -months + 1))

  // Live anchor — identical math to getNetWorth() so the right edge of the
  // chart meets the "Net worth" KPI exactly.
  const accountRows = await db.query.accounts.findMany({
    where: and(eq(accounts.isIncludedInNetWorth, true), eq(accounts.isArchived, false)),
  })
  const currentNet = accountRows.reduce((sum, a) => sum + Number(a.currentBalance), 0)

  // Per-day transaction nets across the window. We don't early-cut on the
  // start date here because we need every transaction on or after `start` to
  // walk back from today. Transfers and archived accounts are excluded so
  // internal moves don't show up as jitter.
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
