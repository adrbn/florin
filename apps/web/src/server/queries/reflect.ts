import { and, asc, eq, gte, isNull, sql } from 'drizzle-orm'
import { db } from '@/db/client'
import { accounts, categories, categoryGroups, transactions } from '@/db/schema'
import { getNetWorth } from './dashboard'

/**
 * Reflect tab queries — analytics summarizing the user's spending and income
 * habits over time. All queries respect the standard filters: not deleted,
 * not transfer pair, not on an archived account.
 */

export interface MonthlyFlow {
  month: string // YYYY-MM
  income: number
  expense: number
  net: number
}

/**
 * Per-month income vs expense aggregation. Used by the income-vs-spending
 * bar chart on the Reflect tab. Always returns `months` rows, padding empty
 * months with zeros so the chart x-axis is continuous.
 */
export async function getMonthlyFlows(months = 12): Promise<MonthlyFlow[]> {
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

  // Build a complete month list and merge in actual data so the chart never
  // has gaps where the user happens to have zero activity.
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

export interface CategoryShare {
  groupName: string
  categoryName: string
  emoji: string | null
  total: number
}

/**
 * Spending by category over a configurable window. Defaults to the trailing
 * 90 days because the user usually wants "recently" not "this calendar month".
 */
export async function getCategoryBreakdown(days = 90): Promise<CategoryShare[]> {
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
 * Age of money — YNAB's signature metric. Approximation:
 *   For each spend over the last N days, look back to find dollar-for-dollar
 *   incoming income that "funded" it (FIFO), then average the days between
 *   the deposit and the spend.
 *
 * We do the FIFO walk in JS because the cohort sizes are small (90 days
 * worth of activity) and the SQL window for this is gnarly.
 */
export async function getAgeOfMoney(days = 90): Promise<number | null> {
  const start = new Date(Date.now() - days * 24 * 60 * 60 * 1000)
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

  // Inflow queue: each item is { date, remaining } sorted oldest first.
  const inflows: { date: Date; remaining: number }[] = []
  const matches: { spendDate: Date; inflowDate: Date; amount: number }[] = []
  for (const row of rows) {
    const amount = Number(row.amount)
    if (amount > 0) {
      inflows.push({ date: row.occurredAt, remaining: amount })
    } else if (amount < 0) {
      let needed = Math.abs(amount)
      while (needed > 0 && inflows.length > 0) {
        const head = inflows[0]
        if (!head) break
        const take = Math.min(head.remaining, needed)
        matches.push({ spendDate: row.occurredAt, inflowDate: head.date, amount: take })
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

export interface NetWorthPoint {
  month: string // YYYY-MM
  /** Cumulative net of all transactions up to end of month, signed. */
  cumulative: number
}

/**
 * Net worth time series anchored on the current account balances. We can't
 * trust a "cumulative cashflow from zero" approach because most users have
 * starting balances that predate any transaction in the DB — that approach
 * was producing charts that floated around 0€ even when net worth was 6500€.
 *
 * Instead: take the live net worth (sum of current account balances) and
 * walk backward by month, subtracting each month's transaction net to get
 * the balance at the END of the previous month. The result is a real net
 * worth curve that lines up with the dashboard "Net worth" KPI on the right
 * edge of the chart.
 */
export async function getNetWorthSeries(months = 24): Promise<NetWorthPoint[]> {
  // Live anchor: same math as the dashboard's getNetWorth (= gross −
  // amortization-based liability for loans).
  const { net: currentNet } = await getNetWorth()

  // Get monthly transaction nets across the whole window so we can walk
  // backwards. Loan accounts are excluded — their mirror rows aren't a
  // cash flow and the liability is already baked into the anchor. See the
  // matching CAVEAT on `getPatrimonyTimeSeries` in dashboard.ts.
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

  // Walk backward: month[0] (most recent) = currentNet, then for each prior
  // month subtract the more-recent month's transactions to get its end balance.
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
