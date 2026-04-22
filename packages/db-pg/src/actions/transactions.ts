import { randomUUID } from 'node:crypto'
import { and, desc, eq, gte, inArray, isNull, lte, ne, sql } from 'drizzle-orm'
import { z } from 'zod'
import { matchRule, normalizePayee, type Rule } from '@florin/core/lib/categorization'
import type {
  ActionResult,
  AddTransactionInput,
  AddTransferInput,
} from '@florin/core/types'
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

const addTransferSchema = z
  .object({
    fromAccountId: z.uuid(),
    toAccountId: z.uuid(),
    amount: z.coerce.number().positive(),
    occurredAt: z.coerce.date(),
    memo: z.string().max(500).optional().nullable(),
  })
  .refine((v) => v.fromAccountId !== v.toAccountId, {
    message: 'Source and destination accounts must differ',
  })

export async function addTransferMutation(
  db: PgDB,
  input: AddTransferInput,
): Promise<ActionResult<{ transferPairId: string }>> {
  const parsed = addTransferSchema.safeParse(input)
  if (!parsed.success) {
    return {
      success: false,
      error: parsed.error.issues.map((i) => i.message).join(', '),
    }
  }
  const data = parsed.data

  try {
    const [fromAcc, toAcc] = await Promise.all([
      db.query.accounts.findFirst({ where: eq(accounts.id, data.fromAccountId) }),
      db.query.accounts.findFirst({ where: eq(accounts.id, data.toAccountId) }),
    ])
    if (!fromAcc || !toAcc) {
      return { success: false, error: 'Account not found' }
    }

    const transferPairId = randomUUID()
    const amount = Math.abs(data.amount)

    await db.insert(transactions).values([
      {
        accountId: data.fromAccountId,
        occurredAt: data.occurredAt,
        amount: (-amount).toFixed(2),
        payee: `Transfer to ${toAcc.name}`,
        normalizedPayee: normalizePayee(`Transfer to ${toAcc.name}`),
        memo: data.memo || null,
        categoryId: null,
        source: 'manual',
        transferPairId,
        needsReview: false,
      },
      {
        accountId: data.toAccountId,
        occurredAt: data.occurredAt,
        amount: amount.toFixed(2),
        payee: `Transfer from ${fromAcc.name}`,
        normalizedPayee: normalizePayee(`Transfer from ${fromAcc.name}`),
        memo: data.memo || null,
        categoryId: null,
        source: 'manual',
        transferPairId,
        needsReview: false,
      },
    ])

    // Pass deltas so bank-synced accounts (enable_banking, pytr) — whose
    // recompute is skipped because the sync API is authoritative — still
    // reflect the money leaving/arriving. For local-ledger accounts the
    // deltas are ignored in favour of a proper `opening + SUM(tx)` recompute.
    await recomputeAccountBalance(db, data.fromAccountId, -amount)
    await recomputeAccountBalance(db, data.toAccountId, amount)

    return { success: true, data: { transferPairId } }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to add transfer'
    return { success: false, error: message }
  }
}

/**
 * Promote an imported transaction into an internal-transfer leg.
 *
 * Accepts an existing (usually review-pending) transaction and a counterpart
 * account. Strategy:
 *   1. Look for a matching counterpart row on `counterpartAccountId` — same
 *      absolute amount, opposite sign, within ±5 days, no existing
 *      `transferPairId`. If found, both rows are linked via a shared
 *      `transferPairId` and cleared from review (`needsReview=false`).
 *   2. If no match, create a synthetic counterpart row on the target account
 *      (opposite sign, same date, payee "Transfer from/to …") so the books
 *      stay balanced. Both rows share the new `transferPairId`.
 *
 * Either way, balances on both accounts are recomputed. Any loan-mirror tied
 * to the source row is cleaned up because transfers never belong to a
 * category (loan mirrors are driven by category).
 */
export async function linkAsInternalTransferMutation(
  db: PgDB,
  transactionId: string,
  counterpartAccountId: string,
): Promise<ActionResult<{ transferPairId: string; mode: 'paired' | 'created' }>> {
  const idParse = z.uuid().safeParse(transactionId)
  if (!idParse.success) return { success: false, error: 'Invalid transaction id' }
  const acctParse = z.uuid().safeParse(counterpartAccountId)
  if (!acctParse.success) return { success: false, error: 'Invalid counterpart account id' }

  try {
    const src = await db.query.transactions.findFirst({
      where: and(eq(transactions.id, transactionId), isNull(transactions.deletedAt)),
    })
    if (!src) return { success: false, error: 'Transaction not found' }
    if (!src.accountId) {
      return { success: false, error: 'Transaction has no account' }
    }
    if (src.accountId === counterpartAccountId) {
      return { success: false, error: 'Counterpart must be a different account' }
    }
    if (src.transferPairId) {
      return { success: false, error: 'Transaction is already part of a transfer' }
    }

    const counterpartAcc = await db.query.accounts.findFirst({
      where: eq(accounts.id, counterpartAccountId),
    })
    if (!counterpartAcc) return { success: false, error: 'Counterpart account not found' }

    const sourceAcc = await db.query.accounts.findFirst({
      where: eq(accounts.id, src.accountId),
    })

    const srcAmount = Number(src.amount)
    const expectedCounterpart = (-srcAmount).toFixed(2)

    // Guard against corrupted occurredAt (legacy rows with invalid timestamps
    // used to crash the whole flow with "Invalid time value" before even
    // reaching the insert). If the date is bad we skip auto-pairing and fall
    // through to creating a shadow leg with "now".
    const srcOccurred =
      src.occurredAt instanceof Date && !Number.isNaN(src.occurredAt.getTime())
        ? src.occurredAt
        : null

    let match: typeof src | undefined = undefined
    if (srcOccurred) {
      const windowMs = 5 * 24 * 60 * 60 * 1000
      const windowStart = new Date(srcOccurred.getTime() - windowMs)
      const windowEnd = new Date(srcOccurred.getTime() + windowMs)
      match = await db.query.transactions.findFirst({
        where: and(
          eq(transactions.accountId, counterpartAccountId),
          isNull(transactions.transferPairId),
          isNull(transactions.deletedAt),
          eq(transactions.amount, expectedCounterpart),
          gte(transactions.occurredAt, windowStart),
          lte(transactions.occurredAt, windowEnd),
        ),
      })
    }

    const transferPairId = randomUUID()
    const now = new Date()

    // Clear any stale loan mirror on the source — transfers never belong to a category.
    const touchedLoanIds = await deleteLoanMirrorFor(db, transactionId)

    await db
      .update(transactions)
      .set({
        transferPairId,
        needsReview: false,
        categoryId: null,
        updatedAt: now,
      })
      .where(eq(transactions.id, transactionId))

    // Balance deltas. The source transaction already existed and its amount
    // didn't change, so source delta is always 0. The counterpart only sees
    // an amount change if we *created* a new shadow leg — paired mode just
    // links two pre-existing rows so balances are already correct.
    let counterpartDelta = 0

    let mode: 'paired' | 'created'
    if (match) {
      await db
        .update(transactions)
        .set({
          transferPairId,
          needsReview: false,
          categoryId: null,
          updatedAt: now,
        })
        .where(eq(transactions.id, match.id))
      await deleteLoanMirrorFor(db, match.id)
      mode = 'paired'
    } else {
      const counterpartPayee = srcAmount < 0
        ? `Transfer to ${counterpartAcc.name}`
        : `Transfer from ${counterpartAcc.name}`
      // The shadow leg uses the opposite sign so the sum stays at zero.
      const amountStr = (-srcAmount).toFixed(2)
      await db.insert(transactions).values({
        accountId: counterpartAccountId,
        occurredAt: srcOccurred ?? now,
        amount: amountStr,
        payee: counterpartPayee,
        normalizedPayee: normalizePayee(counterpartPayee),
        memo: sourceAcc ? `Paired leg of ${sourceAcc.name}` : null,
        categoryId: null,
        source: 'manual',
        transferPairId,
        needsReview: false,
      })
      counterpartDelta = Number(amountStr)
      mode = 'created'
    }

    await recomputeAccountBalance(db, src.accountId, 0)
    await recomputeAccountBalance(db, counterpartAccountId, counterpartDelta)
    for (const loanId of touchedLoanIds) {
      await recomputeAccountBalance(db, loanId)
    }

    return { success: true, data: { transferPairId, mode } }
  } catch (error: unknown) {
    const message =
      error instanceof Error ? error.message : 'Failed to mark as internal transfer'
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
    // Fetch the row first so we know its amount + whether it's one leg of a
    // transfer. We need this to reverse the balance on bank-synced accounts
    // (enable_banking, pytr), whose recompute is skipped in favour of the
    // authoritative sync feed — without a delta their balance wouldn't move.
    const src = await db.query.transactions.findFirst({
      where: and(eq(transactions.id, id), isNull(transactions.deletedAt)),
    })
    if (!src || !src.accountId) {
      return { success: true }
    }

    const touchedLoanIds = await deleteLoanMirrorFor(db, id)
    const now = new Date()

    // Collect every leg we want to delete (the tx itself plus its transfer
    // pair, if any) so we can reverse balances on both accounts.
    const legs: Array<{ id: string; accountId: string; amount: number }> = [
      { id: src.id, accountId: src.accountId, amount: Number(src.amount) },
    ]
    if (src.transferPairId) {
      const pair = await db.query.transactions.findFirst({
        where: and(
          eq(transactions.transferPairId, src.transferPairId),
          isNull(transactions.deletedAt),
          // Exclude the row we already have
          ne(transactions.id, src.id),
        ),
      })
      if (pair && pair.accountId) {
        legs.push({
          id: pair.id,
          accountId: pair.accountId,
          amount: Number(pair.amount),
        })
      }
    }

    await db
      .update(transactions)
      .set({ deletedAt: now, updatedAt: now })
      .where(
        inArray(
          transactions.id,
          legs.map((l) => l.id),
        ),
      )

    for (const leg of legs) {
      // Reverse the leg's contribution: if the leg was -100 (outflow), the
      // balance should go +100 on delete.
      await recomputeAccountBalance(db, leg.accountId, -leg.amount)
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

    const touched = new Set(
      result.map((r) => r.accountId).filter((id): id is string => id !== null),
    )
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
