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
      AND t.transfer_pair_id IS NULL
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
      // spent: sum ABS(amount) for expense-kind categories
      const prev = spentMap.get(tx.categoryId) ?? 0
      spentMap.set(tx.categoryId, prev + Math.abs(tx.amount))
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
  const readyToAssign = Math.round((income - totalAssigned) * 100) / 100
  const overspentCount = groups.reduce((s, g) => s + g.overspentCount, 0)

  return {
    year,
    month,
    groups,
    income,
    totalAssigned,
    readyToAssign,
    overspentCount,
  }
}
