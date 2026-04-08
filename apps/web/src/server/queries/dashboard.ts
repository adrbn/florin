import { and, desc, eq, gte, isNull, lte, sql } from 'drizzle-orm'
import { db } from '@/db/client'
import { accounts, balanceSnapshots, categories, categoryGroups, transactions } from '@/db/schema'

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

export async function getPatrimonyTimeSeries(months = 12): Promise<PatrimonyPoint[]> {
  const start = startOfMonth(addMonths(new Date(), -months + 1))
  const rows = await db
    .select({
      date: balanceSnapshots.snapshotDate,
      balance: balanceSnapshots.balance,
    })
    .from(balanceSnapshots)
    .where(and(isNull(balanceSnapshots.accountId), gte(balanceSnapshots.snapshotDate, start)))
    .orderBy(balanceSnapshots.snapshotDate)
  // Return every snapshot we have — the chart's X-axis is a true time scale
  // (numeric Unix ms), so additional daily snapshots render at their actual
  // calendar position rather than competing with the forecast for category
  // slots. If two snapshots land on the same day we keep the latest one so
  // the curve is single-valued per day.
  const byDay = new Map<string, { date: string; balance: number }>()
  for (const r of rows) {
    const d = r.date instanceof Date ? r.date : new Date(String(r.date))
    const iso = d.toISOString().slice(0, 10)
    byDay.set(iso, { date: iso, balance: Number(r.balance) })
  }
  return Array.from(byDay.values()).sort((a, b) => (a.date < b.date ? -1 : 1))
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
