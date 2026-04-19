import { and, asc, eq, gte, isNull, lt } from 'drizzle-orm'
import type { PgDB } from '../client'
import type { MonthPlan, PlanCategory, PlanGroup } from '@florin/core/types'
import { categories, categoryGroups, transactions, monthlyBudgets } from '../schema'

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

  // ---- 1. All non-archived categories with their group ----
  const catRows = await db
    .select({
      catId: categories.id,
      catName: categories.name,
      catEmoji: categories.emoji,
      catDisplayOrder: categories.displayOrder,
      groupId: categoryGroups.id,
      groupName: categoryGroups.name,
      groupKind: categoryGroups.kind,
      groupColor: categoryGroups.color,
      groupDisplayOrder: categoryGroups.displayOrder,
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
        isNull(transactions.transferPairId),
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
      const prev = spentMap.get(tx.categoryId) ?? 0
      spentMap.set(tx.categoryId, prev + Math.abs(amount))
    }
  }

  income = Math.round(income * 100) / 100

  // ---- Seed group map in order (from catRows which are already sorted) ----
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

  for (const row of catRows) {
    if (!groupMap.has(row.groupId)) {
      groupMap.set(row.groupId, {
        id: row.groupId,
        name: row.groupName,
        kind: row.groupKind,
        color: row.groupColor,
        displayOrder: row.groupDisplayOrder,
        categories: [],
      })
      groupOrder.push(row.groupId)
    }
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
  const totalAssigned = budgetRows.reduce((s, b) => s + parseFloat(b.assigned), 0)
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
