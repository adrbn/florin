import { randomUUID } from 'node:crypto'
import { and, desc, eq, gte, inArray, isNull, lte, ne, sql } from 'drizzle-orm'
import { z } from 'zod'
import { matchRule, normalizePayee, type Rule } from '@florin/core/lib/categorization'
import type {
  ActionResult,
  AddTransactionInput,
  AddTransferInput,
} from '@florin/core/types'
import type { SqliteDB } from '../client'
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
  db: SqliteDB,
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
        occurredAt: data.occurredAt.toISOString().slice(0, 10),
        amount: data.amount,
        payee: data.payee,
        normalizedPayee: normalized,
        memo: data.memo || null,
        categoryId,
        source: 'manual',
      })
      .returning({ id: transactions.id })

    // Pass +data.amount as delta so bank-synced (enable_banking, pytr) and
    // legacy accounts — whose full opening+SUM recompute is skipped — still
    // reflect the new transaction in their cached balance. Local-ledger
    // accounts ignore the delta and run the proper recompute instead.
    await recomputeAccountBalance(db, data.accountId, data.amount)
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

/**
 * Record an internal transfer between two user-owned accounts. Creates two
 * paired rows sharing a `transferPairId` so burn/income metrics ignore them
 * automatically (existing queries already filter by `transferPairId IS NULL`).
 */
export async function addTransferMutation(
  db: SqliteDB,
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
    const dateIso = data.occurredAt.toISOString().slice(0, 10)

    await db.insert(transactions).values([
      {
        accountId: data.fromAccountId,
        occurredAt: dateIso,
        amount: -Math.abs(data.amount),
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
        occurredAt: dateIso,
        amount: Math.abs(data.amount),
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
    const absAmount = Math.abs(data.amount)
    await recomputeAccountBalance(db, data.fromAccountId, -absAmount)
    await recomputeAccountBalance(db, data.toAccountId, absAmount)

    return { success: true, data: { transferPairId } }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to add transfer'
    return { success: false, error: message }
  }
}

/**
 * SQLite twin of `linkAsInternalTransferMutation` (see db-pg for doc).
 * Differences: `occurredAt` is an ISO date string (YYYY-MM-DD), `amount` is a
 * real number, timestamps are stored as ISO strings.
 */
export async function linkAsInternalTransferMutation(
  db: SqliteDB,
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

    // `occurredAt` is a 10-char ISO date ('YYYY-MM-DD'); string compare works as
    // ordered compare. Window is ±5 calendar days. Guard against corrupted
    // values (empty string, undefined, malformed) — those used to crash the
    // flow with "Invalid time value" when toISOString() was called on the
    // resulting Invalid Date. Fall through to shadow-leg creation using today.
    const srcOccurred = (() => {
      if (typeof src.occurredAt !== 'string' || src.occurredAt.length < 10) return null
      const probe = new Date(`${src.occurredAt}T00:00:00Z`)
      return Number.isNaN(probe.getTime()) ? null : src.occurredAt
    })()

    let match: typeof src | undefined = undefined
    if (srcOccurred) {
      const base = new Date(`${srcOccurred}T00:00:00Z`)
      const windowMs = 5 * 24 * 60 * 60 * 1000
      const windowStart = new Date(base.getTime() - windowMs).toISOString().slice(0, 10)
      const windowEnd = new Date(base.getTime() + windowMs).toISOString().slice(0, 10)
      match = await db.query.transactions.findFirst({
        where: and(
          eq(transactions.accountId, counterpartAccountId),
          isNull(transactions.transferPairId),
          isNull(transactions.deletedAt),
          eq(transactions.amount, -srcAmount),
          gte(transactions.occurredAt, windowStart),
          lte(transactions.occurredAt, windowEnd),
        ),
      })
    }

    const transferPairId = randomUUID()
    const nowIso = new Date().toISOString()

    const touchedLoanIds = await deleteLoanMirrorFor(db, transactionId)

    await db
      .update(transactions)
      .set({
        transferPairId,
        needsReview: false,
        categoryId: null,
        updatedAt: nowIso,
      })
      .where(eq(transactions.id, transactionId))

    // Balance deltas. Source tx already existed and its amount didn't change,
    // so source delta is always 0. Counterpart only sees an amount change
    // when we *create* a new shadow leg — paired mode just links two
    // pre-existing rows so balances are already correct.
    let counterpartDelta = 0

    let mode: 'paired' | 'created'
    if (match) {
      await db
        .update(transactions)
        .set({
          transferPairId,
          needsReview: false,
          categoryId: null,
          updatedAt: nowIso,
        })
        .where(eq(transactions.id, match.id))
      await deleteLoanMirrorFor(db, match.id)
      mode = 'paired'
    } else {
      const counterpartPayee = srcAmount < 0
        ? `Transfer to ${counterpartAcc.name}`
        : `Transfer from ${counterpartAcc.name}`
      await db.insert(transactions).values({
        accountId: counterpartAccountId,
        occurredAt: srcOccurred ?? nowIso.slice(0, 10),
        amount: -srcAmount,
        payee: counterpartPayee,
        normalizedPayee: normalizePayee(counterpartPayee),
        memo: sourceAcc ? `Paired leg of ${sourceAcc.name}` : null,
        categoryId: null,
        source: 'manual',
        transferPairId,
        needsReview: false,
      })
      counterpartDelta = -srcAmount
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
  db: SqliteDB,
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
      .set({ categoryId, updatedAt: new Date().toISOString() })
      .where(eq(transactions.id, transactionId))
    await syncLoanMirror(db, transactionId)
    return { success: true }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to update category'
    return { success: false, error: message }
  }
}

export async function softDeleteTransactionMutation(
  db: SqliteDB,
  id: string,
): Promise<ActionResult> {
  const parsed = z.uuid().safeParse(id)
  if (!parsed.success) {
    return { success: false, error: 'Invalid transaction id' }
  }

  try {
    // Fetch first so we know amount + transfer pair. Bank-synced accounts
    // skip opening+SUM recompute, so without a delta their balance never
    // reverses when legs are deleted.
    const src = await db.query.transactions.findFirst({
      where: and(eq(transactions.id, id), isNull(transactions.deletedAt)),
    })
    if (!src || !src.accountId) {
      return { success: true }
    }

    const touchedLoanIds = await deleteLoanMirrorFor(db, id)
    const nowIso = new Date().toISOString()

    const legs: Array<{ id: string; accountId: string; amount: number }> = [
      { id: src.id, accountId: src.accountId, amount: Number(src.amount) },
    ]
    if (src.transferPairId) {
      const pair = await db.query.transactions.findFirst({
        where: and(
          eq(transactions.transferPairId, src.transferPairId),
          isNull(transactions.deletedAt),
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
      .set({ deletedAt: nowIso, updatedAt: nowIso })
      .where(
        inArray(
          transactions.id,
          legs.map((l) => l.id),
        ),
      )

    for (const leg of legs) {
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
  db: SqliteDB,
  transactionId: string,
): Promise<ActionResult> {
  const parsed = z.uuid().safeParse(transactionId)
  if (!parsed.success) return { success: false, error: 'Invalid transaction id' }
  try {
    await db
      .update(transactions)
      .set({ needsReview: false, updatedAt: new Date().toISOString() })
      .where(eq(transactions.id, transactionId))
    return { success: true }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to approve'
    return { success: false, error: message }
  }
}

export async function approveAllTransactionsMutation(
  db: SqliteDB,
): Promise<ActionResult<{ approved: number }>> {
  try {
    const result = await db
      .update(transactions)
      .set({ needsReview: false, updatedAt: new Date().toISOString() })
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
  db: SqliteDB,
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
      .set({ categoryId, updatedAt: new Date().toISOString() })
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
  db: SqliteDB,
  ids: ReadonlyArray<string>,
): Promise<ActionResult<{ approved: number }>> {
  const parsed = bulkIdsSchema.safeParse(ids)
  if (!parsed.success) {
    return { success: false, error: 'Invalid transaction ids' }
  }
  try {
    const result = await db
      .update(transactions)
      .set({ needsReview: false, updatedAt: new Date().toISOString() })
      .where(inArray(transactions.id, parsed.data))
      .returning({ id: transactions.id })
    return { success: true, data: { approved: result.length } }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to approve selection'
    return { success: false, error: message }
  }
}

export async function bulkSoftDeleteTransactionsMutation(
  db: SqliteDB,
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
      .set({ deletedAt: new Date().toISOString(), updatedAt: new Date().toISOString() })
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
  db: SqliteDB,
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
  db: SqliteDB,
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

/**
 * Scan unpaired non-deleted transactions in the last `lookbackDays` and pair
 * obvious internal-transfer matches: same magnitude, opposite signs, on
 * different accounts, within `±toleranceDays` of each other.
 *
 * Conservative on purpose — skips rows where the user already assigned a
 * category, so a misclassified salary/refund won't get silently relabeled as
 * a transfer. Idempotent: rows already carrying a `transferPairId` are
 * ignored, so it's safe to call after every sync.
 */
export async function autoLinkInternalTransfersMutation(
  db: SqliteDB,
  options: { lookbackDays?: number; toleranceDays?: number } = {},
): Promise<ActionResult<{ paired: number }>> {
  const lookback = options.lookbackDays ?? 365
  const tolerance = options.toleranceDays ?? 3

  try {
    const cutoff = new Date(Date.now() - lookback * 86_400_000).toISOString().slice(0, 10)
    const candidates = await db
      .select({
        id: transactions.id,
        accountId: transactions.accountId,
        amount: transactions.amount,
        occurredAt: transactions.occurredAt,
        categoryId: transactions.categoryId,
      })
      .from(transactions)
      .where(
        and(
          isNull(transactions.transferPairId),
          isNull(transactions.deletedAt),
          gte(transactions.occurredAt, cutoff),
        ),
      )

    // Walk the rows in chronological order so deterministic, predictable
    // matches happen first when several candidates collide on the same day.
    const sorted = [...candidates].sort((a, b) => {
      if (a.occurredAt !== b.occurredAt) return a.occurredAt < b.occurredAt ? -1 : 1
      return a.id < b.id ? -1 : 1
    })

    const paired: { a: string; b: string }[] = []
    const used = new Set<string>()

    for (const tx of sorted) {
      if (used.has(tx.id)) continue
      if (tx.categoryId) continue
      if (!tx.accountId) continue
      const txAmount = Number(tx.amount)
      if (!Number.isFinite(txAmount) || txAmount === 0) continue

      const baseTime = new Date(`${tx.occurredAt}T00:00:00Z`).getTime()
      if (Number.isNaN(baseTime)) continue
      const winStart = new Date(baseTime - tolerance * 86_400_000).toISOString().slice(0, 10)
      const winEnd = new Date(baseTime + tolerance * 86_400_000).toISOString().slice(0, 10)

      const match = sorted.find(
        (other) =>
          other.id !== tx.id &&
          !used.has(other.id) &&
          !other.categoryId &&
          other.accountId &&
          other.accountId !== tx.accountId &&
          Number(other.amount) === -txAmount &&
          other.occurredAt >= winStart &&
          other.occurredAt <= winEnd,
      )
      if (match) {
        used.add(tx.id)
        used.add(match.id)
        paired.push({ a: tx.id, b: match.id })
      }
    }

    const nowIso = new Date().toISOString()
    for (const { a, b } of paired) {
      const transferPairId = randomUUID()
      await db
        .update(transactions)
        .set({ transferPairId, needsReview: false, updatedAt: nowIso })
        .where(inArray(transactions.id, [a, b]))
    }

    return { success: true, data: { paired: paired.length } }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to auto-link transfers'
    return { success: false, error: message }
  }
}
