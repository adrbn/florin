import type { SqliteDB } from '../client'
import type { MonthPlan, PlanCategory, PlanGroup } from '@florin/core/types'

/**
 * Synchronous query that builds the full MonthPlan for a given (year, month).
 *
 * Uses .all() / .get() (better-sqlite3 sync API) so callers don't need await.
 */
export function getMonthPlanQuery(db: SqliteDB, year: number, month: number): MonthPlan {
  // ---- date boundaries (lexicographic compare works for ISO strings) ----
  const start = `${year}-${String(month).padStart(2, '0')}-01`
  const end =
    month === 12
      ? `${year + 1}-01-01`
      : `${year}-${String(month + 1).padStart(2, '0')}-01`

  // ---- 0. All expense groups (including empty ones) ----
  type GroupRow = {
    groupId: string
    groupName: string
    groupKind: string
    groupColor: string | null
    groupDisplayOrder: number
  }

  const groupSql = `
    SELECT
      id           AS groupId,
      name         AS groupName,
      kind         AS groupKind,
      color        AS groupColor,
      display_order AS groupDisplayOrder
    FROM category_groups
    ORDER BY display_order ASC, name ASC
  `

  // ---- 1. All non-archived categories with their group ----
  type CatRow = {
    catId: string
    catName: string
    catEmoji: string | null
    catDisplayOrder: number
    groupId: string
    groupKind: string
  }

  const catSql = `
    SELECT
      c.id           AS catId,
      c.name         AS catName,
      c.emoji        AS catEmoji,
      c.display_order AS catDisplayOrder,
      g.id           AS groupId,
      g.kind         AS groupKind
    FROM categories c
    INNER JOIN category_groups g ON c.group_id = g.id
    WHERE c.is_archived = 0
    ORDER BY g.display_order ASC, g.name ASC, c.display_order ASC, c.name ASC
  `

  // ---- 2. Budget rows for (year, month) ----
  const budgetSql = `
    SELECT category_id AS categoryId, assigned, note
    FROM monthly_budgets
    WHERE year = ? AND month = ?
  `

  // ---- 3. Transactions for the month ----
  const txSql = `
    SELECT
      t.category_id  AS categoryId,
      t.amount       AS amount,
      g.kind         AS groupKind
    FROM transactions t
    LEFT JOIN categories c ON t.category_id = c.id
    LEFT JOIN category_groups g ON c.group_id = g.id
    WHERE t.occurred_at >= ?
      AND t.occurred_at < ?
      AND t.deleted_at IS NULL
      AND (t.transfer_pair_id IS NULL
           OR (t.amount < 0 AND EXISTS (
             SELECT 1 FROM transactions p
             JOIN accounts pa ON pa.id = p.account_id
             WHERE p.transfer_pair_id = t.transfer_pair_id
               AND p.id <> t.id AND pa.kind = 'loan')))
  `

  // Access the underlying better-sqlite3 instance via drizzle's public $client property.
  const rawDb = (db as unknown as { $client: import('better-sqlite3').Database }).$client

  const groupResults = rawDb.prepare(groupSql).all() as GroupRow[]
  const catResults = rawDb.prepare(catSql).all() as CatRow[]
  const budgetResults = rawDb.prepare(budgetSql).all(year, month) as {
    categoryId: string
    assigned: number
    note: string | null
  }[]
  const txResults = rawDb.prepare(txSql).all(start, end) as {
    categoryId: string | null
    amount: number
    groupKind: string | null
  }[]

  // ---- Build budget map ----
  const budgetMap = new Map<string, { assigned: number; note: string | null }>()
  for (const b of budgetResults) {
    budgetMap.set(b.categoryId, { assigned: b.assigned, note: b.note })
  }

  // ---- Build per-category spent map (expense groups only) ----
  const spentMap = new Map<string, number>()
  let income = 0

  for (const tx of txResults) {
    if (tx.categoryId === null) continue

    if (tx.groupKind === 'income') {
      // income: sum amount (positive for salary txs)
      income += tx.amount
    } else if (tx.groupKind === 'expense') {
      // YNAB Activity semantics: spent = -signed(amount). Outflows (stored
      // negative) become +spent; refunds (stored positive) reduce spent.
      // Math.abs was double-counting refunds as if they were expenses.
      const prev = spentMap.get(tx.categoryId) ?? 0
      spentMap.set(tx.categoryId, prev - tx.amount)
    }
  }

  // Round income to cents
  income = Math.round(income * 100) / 100

  // ---- Build group map (seed with all groups, including empty ones) ----
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

  for (const g of groupResults) {
    groupMap.set(g.groupId, {
      id: g.groupId,
      name: g.groupName,
      kind: g.groupKind,
      color: g.groupColor,
      displayOrder: g.groupDisplayOrder,
      categories: [],
    })
    groupOrder.push(g.groupId)
  }

  // ---- Populate categories into expense groups ----
  for (const row of catResults) {
    // Only expense groups have PlanCategory entries; income groups excluded from groups[]
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

  // ---- Build PlanGroup[] (expense only), ordered by displayOrder then name ----
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
  const totalAssigned = Math.round(budgetResults.reduce((s, b) => s + b.assigned, 0) * 100) / 100

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
  const monthIsOver = end <= new Date().toISOString().slice(0, 10)
  let expectedIncome = income
  let incomeIsEstimated = false
  if (!monthIsOver) {
    const typical = median(getRecentMonthlyIncome(rawDb, start))
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
function getRecentMonthlyIncome(
  db: import('better-sqlite3').Database,
  before: string,
): number[] {
  const rows = db
    .prepare(
      `SELECT substr(t.occurred_at, 1, 7) AS month, SUM(t.amount) AS total
       FROM transactions t
       JOIN categories c ON c.id = t.category_id
       JOIN category_groups g ON g.id = c.group_id
       WHERE t.deleted_at IS NULL AND g.kind = 'income' AND t.amount > 0
         AND t.transfer_pair_id IS NULL
         AND substr(t.occurred_at, 1, 10) >= date(?, '-6 months')
         AND substr(t.occurred_at, 1, 10) < ?
       GROUP BY month`,
    )
    .all(before, before) as { month: string; total: number }[]
  return rows.map((r) => Number(r.total ?? 0)).filter((n) => n > 0)
}
