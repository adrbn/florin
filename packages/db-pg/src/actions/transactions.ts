import { and, desc, eq, inArray, isNull, sql } from 'drizzle-orm'
import { z } from 'zod'
import { matchRule, normalizePayee, type Rule } from '@florin/core/lib/categorization'
import type { ActionResult, AddTransactionInput } from '@florin/core/types'
import type { PgDB } from '../client'
import { accounts, categories, categorizationRules, transactions } from '../schema'
import {
  recomputeAccountBalance,
  syncLoanMirror,
  deleteLoanMirrorFor,
} from './helpers'

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

export async function addTransactionMutation(
  db: PgDB,
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

    await recomputeAccountBalance(db, data.accountId)
    if (row?.id) await syncLoanMirror(db, row.id)

    return { success: true, data: { id: row?.id ?? '' } }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to add transaction'
    return { success: false, error: message }
  }
}

export async function updateTransactionCategoryMutation(
  db: PgDB,
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
    await syncLoanMirror(db, transactionId)
    return { success: true }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to update category'
    return { success: false, error: message }
  }
}

export async function softDeleteTransactionMutation(
  db: PgDB,
  id: string,
): Promise<ActionResult> {
  const parsed = z.uuid().safeParse(id)
  if (!parsed.success) {
    return { success: false, error: 'Invalid transaction id' }
  }

  try {
    const touchedLoanIds = await deleteLoanMirrorFor(db, id)

    const [txn] = await db
      .update(transactions)
      .set({ deletedAt: new Date(), updatedAt: new Date() })
      .where(eq(transactions.id, id))
      .returning({ accountId: transactions.accountId })

    if (txn) {
      await recomputeAccountBalance(db, txn.accountId)
    }
    for (const loanId of touchedLoanIds) {
      await recomputeAccountBalance(db, loanId)
    }

    return { success: true }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to delete transaction'
    return { success: false, error: message }
  }
}

export async function approveTransactionMutation(
  db: PgDB,
  transactionId: string,
): Promise<ActionResult> {
  const parsed = z.uuid().safeParse(transactionId)
  if (!parsed.success) return { success: false, error: 'Invalid transaction id' }
  try {
    await db
      .update(transactions)
      .set({ needsReview: false, updatedAt: new Date() })
      .where(eq(transactions.id, transactionId))
    return { success: true }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to approve'
    return { success: false, error: message }
  }
}

export async function approveAllTransactionsMutation(
  db: PgDB,
): Promise<ActionResult<{ approved: number }>> {
  try {
    const result = await db
      .update(transactions)
      .set({ needsReview: false, updatedAt: new Date() })
      .where(eq(transactions.needsReview, true))
      .returning({ id: transactions.id })
    return { success: true, data: { approved: result.length } }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to bulk approve'
    return { success: false, error: message }
  }
}

const bulkIdsSchema = z.array(z.uuid()).min(1).max(500)

export async function bulkUpdateTransactionCategoryMutation(
  db: PgDB,
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
    for (const row of result) {
      await syncLoanMirror(db, row.id)
    }
    return { success: true, data: { updated: result.length } }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to update categories'
    return { success: false, error: message }
  }
}

export async function bulkApproveTransactionsMutation(
  db: PgDB,
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
    return { success: true, data: { approved: result.length } }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to approve selection'
    return { success: false, error: message }
  }
}

export async function bulkSoftDeleteTransactionsMutation(
  db: PgDB,
  ids: ReadonlyArray<string>,
): Promise<ActionResult<{ deleted: number }>> {
  const parsed = bulkIdsSchema.safeParse(ids)
  if (!parsed.success) {
    return { success: false, error: 'Invalid transaction ids' }
  }
  try {
    const loanAccountIdsTouched = new Set<string>()
    for (const id of parsed.data) {
      const loanIds = await deleteLoanMirrorFor(db, id)
      for (const loanId of loanIds) loanAccountIdsTouched.add(loanId)
    }

    const result = await db
      .update(transactions)
      .set({ deletedAt: new Date(), updatedAt: new Date() })
      .where(inArray(transactions.id, parsed.data))
      .returning({ accountId: transactions.accountId })

    const touched = new Set(result.map((r) => r.accountId))
    for (const accountId of touched) {
      await recomputeAccountBalance(db, accountId)
    }
    for (const loanId of loanAccountIdsTouched) {
      await recomputeAccountBalance(db, loanId)
    }

    return { success: true, data: { deleted: result.length } }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to delete transactions'
    return { success: false, error: message }
  }
}

/**
 * List transactions for an account. Used by account detail pages.
 */
export async function listTransactionsForAccountQuery(
  db: PgDB,
  accountId: string,
  limit = 500,
) {
  return db.query.transactions.findMany({
    where: and(eq(transactions.accountId, accountId), isNull(transactions.deletedAt)),
    orderBy: [desc(transactions.occurredAt), desc(transactions.createdAt)],
    limit,
    with: {
      account: true,
      category: true,
    },
  })
}

/**
 * Payments list for a loan account detail page.
 */
export async function listLoanPaymentsForAccountQuery(
  db: PgDB,
  loanAccountId: string,
  limit = 500,
) {
  const linkedCategoryRows = await db
    .select({ id: categories.id })
    .from(categories)
    .where(eq(categories.linkedLoanAccountId, loanAccountId))
  const linkedCategoryIds = linkedCategoryRows.map((r) => r.id)

  const whereClause =
    linkedCategoryIds.length > 0
      ? and(
          isNull(transactions.deletedAt),
          sql`(${inArray(transactions.categoryId, linkedCategoryIds)} OR (${eq(transactions.accountId, loanAccountId)} AND ${isNull(transactions.transferPairId)}))`,
        )
      : and(
          isNull(transactions.deletedAt),
          eq(transactions.accountId, loanAccountId),
          isNull(transactions.transferPairId),
        )

  return db.query.transactions.findMany({
    where: whereClause,
    orderBy: [desc(transactions.occurredAt), desc(transactions.createdAt)],
    limit,
    with: {
      account: true,
      category: true,
    },
  })
}
