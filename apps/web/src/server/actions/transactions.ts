'use server'

import { and, asc, desc, eq, gte, inArray, isNull, lte, sql } from 'drizzle-orm'
import { revalidatePath } from 'next/cache'
import { z } from 'zod'
import { db } from '@/db/client'
import { accounts, categorizationRules, transactions } from '@/db/schema'
import { matchRule, type Rule } from '@/lib/categorization/engine'
import { normalizePayee } from '@/lib/categorization/normalize-payee'

const addTransactionSchema = z.object({
  accountId: z.uuid(),
  occurredAt: z.coerce.date(),
  amount: z.coerce.number(),
  payee: z.string().min(1).max(200),
  memo: z.string().max(500).optional().nullable(),
  categoryId: z
    .union([z.uuid(), z.literal('')])
    .optional()
    .nullable(),
})

export type AddTransactionInput = z.infer<typeof addTransactionSchema>

export interface ActionResult<T = void> {
  success: boolean
  error?: string
  data?: T
}

async function recomputeAccountBalance(accountId: string): Promise<void> {
  const result = await db
    .select({
      total: sql<string>`COALESCE(SUM(${transactions.amount}), 0)::text`,
    })
    .from(transactions)
    .where(and(eq(transactions.accountId, accountId), isNull(transactions.deletedAt)))

  const total = result[0]?.total ?? '0'
  await db
    .update(accounts)
    .set({ currentBalance: total, updatedAt: new Date() })
    .where(eq(accounts.id, accountId))
}

export async function addTransaction(
  input: AddTransactionInput,
): Promise<ActionResult<{ id: string }>> {
  const parsed = addTransactionSchema.safeParse(input)
  if (!parsed.success) {
    return {
      success: false,
      error: parsed.error.issues.map((i) => i.message).join(', '),
    }
  }
  const data = parsed.data

  try {
    const normalized = normalizePayee(data.payee)

    let categoryId: string | null =
      data.categoryId && data.categoryId !== '' ? data.categoryId : null

    if (!categoryId) {
      const rules = await db.select().from(categorizationRules)
      const ruleSet: Rule[] = rules.map((r) => ({
        id: r.id,
        priority: r.priority,
        categoryId: r.categoryId,
        isActive: r.isActive,
        matchPayeeRegex: r.matchPayeeRegex,
        matchMinAmount: r.matchMinAmount ? Number(r.matchMinAmount) : null,
        matchMaxAmount: r.matchMaxAmount ? Number(r.matchMaxAmount) : null,
        matchAccountId: r.matchAccountId,
      }))

      categoryId = matchRule(
        {
          payee: normalized,
          amount: data.amount,
          accountId: data.accountId,
        },
        ruleSet,
      )
    }

    const [row] = await db
      .insert(transactions)
      .values({
        accountId: data.accountId,
        occurredAt: data.occurredAt,
        amount: data.amount.toFixed(2),
        payee: data.payee,
        normalizedPayee: normalized,
        memo: data.memo || null,
        categoryId,
        source: 'manual',
      })
      .returning({ id: transactions.id })

    await recomputeAccountBalance(data.accountId)

    revalidatePath('/transactions')
    revalidatePath('/accounts')
    revalidatePath('/')

    return { success: true, data: { id: row?.id ?? '' } }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to add transaction'
    return { success: false, error: message }
  }
}

export type TransactionDirection = 'all' | 'expense' | 'income'

export interface ListTransactionsOptions {
  limit?: number
  accountId?: string
  needsReviewOnly?: boolean
  /** Inclusive lower bound on occurred_at. */
  startDate?: Date
  /** Inclusive upper bound on occurred_at. */
  endDate?: Date
  /** 'expense' → amount < 0, 'income' → amount > 0, 'all' → no filter. */
  direction?: TransactionDirection
  /** Drop transactions that are one side of an internal transfer. Matches
   *  the dashboard Burn/Income math so click-through from a KPI card shows
   *  exactly the same rows the KPI counted. */
  excludeTransfers?: boolean
}

export async function listTransactions(options: ListTransactionsOptions = {}) {
  const {
    limit = 100,
    accountId,
    needsReviewOnly = false,
    startDate,
    endDate,
    direction = 'all',
    excludeTransfers = false,
  } = options
  // Subquery: ids of accounts the user still cares about (not archived).
  // Excluding archived accounts here keeps the Transactions page in sync with
  // the dashboard widgets, which already filter the same way.
  const activeAccountIds = db
    .select({ id: accounts.id })
    .from(accounts)
    .where(eq(accounts.isArchived, false))
  const conditions = [
    isNull(transactions.deletedAt),
    inArray(transactions.accountId, activeAccountIds),
  ]
  if (accountId) conditions.push(eq(transactions.accountId, accountId))
  if (needsReviewOnly) conditions.push(eq(transactions.needsReview, true))
  if (startDate) conditions.push(gte(transactions.occurredAt, startDate))
  if (endDate) conditions.push(lte(transactions.occurredAt, endDate))
  if (direction === 'expense') {
    conditions.push(sql`${transactions.amount} < 0`)
  } else if (direction === 'income') {
    conditions.push(sql`${transactions.amount} > 0`)
  }
  if (excludeTransfers) {
    conditions.push(isNull(transactions.transferPairId))
  }
  return db.query.transactions.findMany({
    where: and(...conditions),
    orderBy: [desc(transactions.occurredAt), desc(transactions.createdAt)],
    limit,
    with: {
      account: true,
      category: true,
    },
  })
}

/**
 * Count of transactions sitting in the review queue. Drives the sidebar badge
 * so the user knows there's bank-imported activity waiting for them.
 */
export async function countNeedsReview(): Promise<number> {
  const rows = await db
    .select({ count: sql<string>`COUNT(*)` })
    .from(transactions)
    .innerJoin(accounts, eq(transactions.accountId, accounts.id))
    .where(
      and(
        isNull(transactions.deletedAt),
        eq(transactions.needsReview, true),
        eq(accounts.isArchived, false),
      ),
    )
  return Number(rows[0]?.count ?? '0')
}

/**
 * Approve one transaction (clear the needs_review flag). Used by the review
 * queue page after the user has confirmed payee + category.
 */
export async function approveTransaction(transactionId: string): Promise<ActionResult> {
  const parsed = z.uuid().safeParse(transactionId)
  if (!parsed.success) return { success: false, error: 'Invalid transaction id' }
  try {
    await db
      .update(transactions)
      .set({ needsReview: false, updatedAt: new Date() })
      .where(eq(transactions.id, transactionId))
    revalidatePath('/review')
    revalidatePath('/transactions')
    revalidatePath('/')
    return { success: true }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to approve'
    return { success: false, error: message }
  }
}

/**
 * Approve every pending review row in one shot. Useful when the user trusts
 * the bank import after eyeballing the queue and just wants to bulk-clear it.
 */
export async function approveAllTransactions(): Promise<ActionResult<{ approved: number }>> {
  try {
    const result = await db
      .update(transactions)
      .set({ needsReview: false, updatedAt: new Date() })
      .where(eq(transactions.needsReview, true))
      .returning({ id: transactions.id })
    revalidatePath('/review')
    revalidatePath('/transactions')
    revalidatePath('/')
    return { success: true, data: { approved: result.length } }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to bulk approve'
    return { success: false, error: message }
  }
}

// Sort + filter helpers used by account detail pages.
export async function listTransactionsForAccount(
  accountId: string,
  limit = 500,
): Promise<TransactionWithRelations[]> {
  return db.query.transactions.findMany({
    where: and(eq(transactions.accountId, accountId), isNull(transactions.deletedAt)),
    orderBy: [desc(transactions.occurredAt), desc(transactions.createdAt)],
    limit,
    with: {
      account: true,
      category: true,
    },
  }) as Promise<TransactionWithRelations[]>
}

// Re-export asc to keep tree-shaking happy in callers that need ordering helpers.
export { asc }

export type TransactionWithRelations = Awaited<ReturnType<typeof listTransactions>>[number]

/**
 * Reassign one transaction to a different category (or clear it). Used by the
 * inline category picker on the Transactions page.
 */
export async function updateTransactionCategory(
  transactionId: string,
  categoryId: string | null,
): Promise<ActionResult> {
  const idParse = z.uuid().safeParse(transactionId)
  if (!idParse.success) return { success: false, error: 'Invalid transaction id' }
  if (categoryId !== null) {
    const catParse = z.uuid().safeParse(categoryId)
    if (!catParse.success) return { success: false, error: 'Invalid category id' }
  }
  try {
    await db
      .update(transactions)
      .set({ categoryId, updatedAt: new Date() })
      .where(eq(transactions.id, transactionId))
    revalidatePath('/transactions')
    revalidatePath('/')
    revalidatePath('/categories')
    return { success: true }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to update category'
    return { success: false, error: message }
  }
}

export async function softDeleteTransaction(id: string): Promise<ActionResult> {
  const parsed = z.uuid().safeParse(id)
  if (!parsed.success) {
    return { success: false, error: 'Invalid transaction id' }
  }

  try {
    const [txn] = await db
      .update(transactions)
      .set({ deletedAt: new Date(), updatedAt: new Date() })
      .where(eq(transactions.id, id))
      .returning({ accountId: transactions.accountId })

    if (txn) {
      await recomputeAccountBalance(txn.accountId)
    }

    revalidatePath('/transactions')
    revalidatePath('/review')
    revalidatePath('/accounts')
    revalidatePath('/')
    return { success: true }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to delete transaction'
    return { success: false, error: message }
  }
}

// ============ bulk actions ============

const bulkIdsSchema = z.array(z.uuid()).min(1).max(500)

/**
 * Reassign a category (or clear it) for many transactions in one shot.
 * Used by the multi-select bulk bar on the Review and Transactions pages so
 * the user can burn through a queue like "all 12 PAYPAL rows → Food" without
 * opening the picker 12 times.
 */
export async function bulkUpdateTransactionCategory(
  ids: ReadonlyArray<string>,
  categoryId: string | null,
): Promise<ActionResult<{ updated: number }>> {
  const parsed = bulkIdsSchema.safeParse(ids)
  if (!parsed.success) {
    return { success: false, error: 'Invalid transaction ids' }
  }
  if (categoryId !== null) {
    const catParse = z.uuid().safeParse(categoryId)
    if (!catParse.success) return { success: false, error: 'Invalid category id' }
  }
  try {
    const result = await db
      .update(transactions)
      .set({ categoryId, updatedAt: new Date() })
      .where(inArray(transactions.id, parsed.data))
      .returning({ id: transactions.id })
    revalidatePath('/transactions')
    revalidatePath('/review')
    revalidatePath('/')
    revalidatePath('/categories')
    return { success: true, data: { updated: result.length } }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to update categories'
    return { success: false, error: message }
  }
}

/**
 * Approve a specific subset of review rows. Unlike approveAllTransactions,
 * this one scopes to the ids the user explicitly ticked — the Review page
 * uses it when the bulk bar is active but the user only selected some rows.
 */
export async function bulkApproveTransactions(
  ids: ReadonlyArray<string>,
): Promise<ActionResult<{ approved: number }>> {
  const parsed = bulkIdsSchema.safeParse(ids)
  if (!parsed.success) {
    return { success: false, error: 'Invalid transaction ids' }
  }
  try {
    const result = await db
      .update(transactions)
      .set({ needsReview: false, updatedAt: new Date() })
      .where(inArray(transactions.id, parsed.data))
      .returning({ id: transactions.id })
    revalidatePath('/review')
    revalidatePath('/transactions')
    revalidatePath('/')
    return { success: true, data: { approved: result.length } }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to approve selection'
    return { success: false, error: message }
  }
}

/**
 * Soft-delete many transactions, then recompute the balance of every account
 * that was touched (each account only once, even if many of its rows were
 * deleted). Mirrors softDeleteTransaction but batched.
 */
export async function bulkSoftDeleteTransactions(
  ids: ReadonlyArray<string>,
): Promise<ActionResult<{ deleted: number }>> {
  const parsed = bulkIdsSchema.safeParse(ids)
  if (!parsed.success) {
    return { success: false, error: 'Invalid transaction ids' }
  }
  try {
    const result = await db
      .update(transactions)
      .set({ deletedAt: new Date(), updatedAt: new Date() })
      .where(inArray(transactions.id, parsed.data))
      .returning({ accountId: transactions.accountId })

    const touched = new Set(result.map((r) => r.accountId))
    for (const accountId of touched) {
      await recomputeAccountBalance(accountId)
    }

    revalidatePath('/transactions')
    revalidatePath('/review')
    revalidatePath('/accounts')
    revalidatePath('/')
    return { success: true, data: { deleted: result.length } }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to delete transactions'
    return { success: false, error: message }
  }
}
