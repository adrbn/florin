import { and, asc, eq, gte, isNull, lt, sql } from 'drizzle-orm'
import type { PgDB } from '../client'
import type { MonthPlan, PlanCategory, PlanGroup } from '@florin/core/types'
import { accounts, categories, categoryGroups, transactions, monthlyBudgets } from '../schema'

/**
 * Async query that builds the full MonthPlan for a given (year, month).
 *
 * Mirrors the SQLite getMonthPlanQuery algorithm exactly. Key PG differences:
 * - numeric columns (amount, assigned) are returned as strings → parseFloat() before arithmetic
 * - occurredAt is a Date object → use drizzle gte/lt with Date objects directly
 */
export async function getMonthPlanQuery(
  db: PgDB,
  year: number,
  month: number,
): Promise<MonthPlan> {
  // ---- date boundaries ----
  const start = new Date(Date.UTC(year, month - 1, 1))
  const end = new Date(Date.UTC(year, month, 1)) // month=12 → Jan 1 of year+1, JS handles rollover

  // ---- 0. All expense-kind groups (including empty ones) ----
  const expenseGroups = await db
    .select({
      id: categoryGroups.id,
      name: categoryGroups.name,
      color: categoryGroups.color,
      displayOrder: categoryGroups.displayOrder,
    })
    .from(categoryGroups)
    .where(eq(categoryGroups.kind, 'expense'))
    .orderBy(asc(categoryGroups.displayOrder), asc(categoryGroups.name))

  // ---- 1. All non-archived categories with their group ----
  const catRows = await db
    .select({
      catId: categories.id,
      catName: categories.name,
      catEmoji: categories.emoji,
      catDisplayOrder: categories.displayOrder,
      groupId: categoryGroups.id,
      groupKind: categoryGroups.kind,
    })
    .from(categories)
    .innerJoin(categoryGroups, eq(categories.groupId, categoryGroups.id))
    .where(eq(categories.isArchived, false))
    .orderBy(
      asc(categoryGroups.displayOrder),
      asc(categoryGroups.name),
      asc(categories.displayOrder),
      asc(categories.name),
    )

  // ---- 2. Budget rows for (year, month) ----
  const budgetRows = await db
    .select({
      categoryId: monthlyBudgets.categoryId,
      assigned: monthlyBudgets.assigned,
      note: monthlyBudgets.note,
    })
    .from(monthlyBudgets)
    .where(and(eq(monthlyBudgets.year, year), eq(monthlyBudgets.month, month)))

  // ---- 3. Transactions for the month ----
  const txRows = await db
    .select({
      categoryId: transactions.categoryId,
      amount: transactions.amount,
      groupKind: categoryGroups.kind,
    })
    .from(transactions)
    .leftJoin(categories, eq(transactions.categoryId, categories.id))
    .leftJoin(categoryGroups, eq(categories.groupId, categoryGroups.id))
    .where(
      and(
        gte(transactions.occurredAt, start),
        lt(transactions.occurredAt, end),
        isNull(transactions.deletedAt),
        // A leg of a transfer is not spending — unless the money is settling
        // a debt. Feeding your own savings is not a bill; a loan repayment is
        // one you budget for and watch leave every month, and excluding both
        // legs reported "Réparti 136 €, dépensé 0 €" for it. The counterpart's
        // account decides, not whether someone filed the row: a transfer to
        // savings with a category on it is still a transfer.
        sql`(${transactions.transferPairId} IS NULL
             OR (${transactions.amount} < 0 AND EXISTS (
               SELECT 1 FROM ${transactions} AS p
               JOIN ${accounts} AS pa ON pa.id = p.account_id
               WHERE p.transfer_pair_id = ${transactions.transferPairId}
                 AND p.id <> ${transactions.id} AND pa.kind = 'loan')))`,
      ),
    )

  // ---- Build budget map (parse numeric string → number) ----
  const budgetMap = new Map<string, { assigned: number; note: string | null }>()
  for (const b of budgetRows) {
    budgetMap.set(b.categoryId, {
      assigned: parseFloat(b.assigned),
      note: b.note,
    })
  }

  // ---- Build per-category spent map + income (parse numeric strings) ----
  const spentMap = new Map<string, number>()
  let income = 0

  for (const tx of txRows) {
    if (tx.categoryId === null) continue

    const amount = parseFloat(tx.amount)

    if (tx.groupKind === 'income') {
      income += amount
    } else if (tx.groupKind === 'expense') {
      // YNAB Activity semantics: spent = -signed(amount). Expense outflows
      // (stored negative → +50 spent), refunds/reimbursements (stored positive
      // → -33.30 reducing spent). Math.abs was double-counting refunds.
      const prev = spentMap.get(tx.categoryId) ?? 0
      spentMap.set(tx.categoryId, prev - amount)
    }
  }

  income = Math.round(income * 100) / 100

  // ---- Seed group map from expenseGroups first (preserves empty groups) ----
  type GroupAcc = {
    id: string
    name: string
    kind: string
    color: string | null
    displayOrder: number
    categories: PlanCategory[]
  }

  const groupMap = new Map<string, GroupAcc>()
  const groupOrder: string[] = []

  for (const g of expenseGroups) {
    groupMap.set(g.id, {
      id: g.id,
      name: g.name,
      kind: 'expense',
      color: g.color,
      displayOrder: g.displayOrder,
      categories: [],
    })
    groupOrder.push(g.id)
  }

  // ---- Populate categories into expense groups ----
  for (const row of catRows) {
    if (row.groupKind !== 'expense') continue

    const budget = budgetMap.get(row.catId)
    const assigned = budget?.assigned ?? 0
    const spent = Math.round((spentMap.get(row.catId) ?? 0) * 100) / 100
    const available = Math.round((assigned - spent) * 100) / 100

    const planCat: PlanCategory = {
      id: row.catId,
      name: row.catName,
      emoji: row.catEmoji,
      assigned,
      spent,
      available,
      note: budget?.note ?? null,
    }

    groupMap.get(row.groupId)!.categories.push(planCat)
  }

  // ---- Build PlanGroup[] (expense only), in seeded order ----
  const groups: PlanGroup[] = []

  for (const gid of groupOrder) {
    const g = groupMap.get(gid)!
    if (g.kind !== 'expense') continue

    const gAssigned = g.categories.reduce((s, c) => s + c.assigned, 0)
    const gSpent = Math.round(g.categories.reduce((s, c) => s + c.spent, 0) * 100) / 100
    const gAvailable = Math.round((gAssigned - gSpent) * 100) / 100
    const overspentCount = g.categories.filter((c) => c.assigned > 0 && c.available < 0).length

    groups.push({
      id: g.id,
      name: g.name,
      kind: 'expense',
      color: g.color,
      categories: g.categories,
      assigned: gAssigned,
      spent: gSpent,
      available: gAvailable,
      overspentCount,
    })
  }

  // ---- totalAssigned = sum of ALL budget rows for this month ----
  const totalAssigned = Math.round(budgetRows.reduce((s, b) => s + parseFloat(b.assigned), 0) * 100) / 100

  /*
   * A month still running is planned against what it will bring in.
   *
   * `income` is what has landed, and a salary lands around the 27th — so for
   * twenty-six days of every month the plan was measured against a figure
   * that had nothing to do with it, announcing "sur 0 € de revenus" and
   * calling a perfectly ordinary plan an overspend.
   *
   * The median of the six complete months before it is the estimate: robust
   * where a mean is not, since one month carrying a 500 € cheque or a tax
   * refund should not raise what the next is expected to earn. A month that
   * is over keeps its own figure — there is nothing left to estimate.
   */
  const monthIsOver = end <= new Date()
  let expectedIncome = income
  let incomeIsEstimated = false
  if (!monthIsOver) {
    const history = await getRecentMonthlyIncome(db, start)
    const typical = median(history)
    if (typical > income) {
      expectedIncome = Math.round(typical * 100) / 100
      incomeIsEstimated = true
    }
  }
  const readyToAssign = Math.round((expectedIncome - totalAssigned) * 100) / 100
  const overspentCount = groups.reduce((s, g) => s + g.overspentCount, 0)

  return {
    year,
    month,
    groups,
    income,
    expectedIncome,
    incomeIsEstimated,
    totalAssigned,
    readyToAssign,
    overspentCount,
  }
}

/** The middle value, or the mean of the two middle ones. Zero when empty. */
function median(values: number[]): number {
  if (values.length === 0) return 0
  const sorted = [...values].sort((a, b) => a - b)
  const middle = Math.floor(sorted.length / 2)
  const high = sorted[middle] ?? 0
  const low = sorted[middle - 1] ?? high
  return sorted.length % 2 === 1 ? high : (low + high) / 2
}

/**
 * Income per complete month for the six months before `before`, months with
 * none omitted — a ledger that starts mid-history should not be told it earns
 * nothing every other month.
 */
async function getRecentMonthlyIncome(db: PgDB, before: Date): Promise<number[]> {
  const from = new Date(Date.UTC(before.getUTCFullYear(), before.getUTCMonth() - 6, 1))
  const rows = await db
    .select({
      month: sql<string>`to_char(${transactions.occurredAt}, 'YYYY-MM')`,
      total: sql<string>`SUM(${transactions.amount})`,
    })
    .from(transactions)
    .innerJoin(categories, eq(transactions.categoryId, categories.id))
    .innerJoin(categoryGroups, eq(categories.groupId, categoryGroups.id))
    .where(
      and(
        isNull(transactions.deletedAt),
        eq(categoryGroups.kind, 'income'),
        sql`${transactions.amount} > 0`,
        isNull(transactions.transferPairId),
        gte(transactions.occurredAt, from),
        lt(transactions.occurredAt, before),
      ),
    )
    .groupBy(sql`to_char(${transactions.occurredAt}, 'YYYY-MM')`)
  return rows.map((r) => Number(r.total ?? '0')).filter((n) => n > 0)
}
