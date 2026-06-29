import { and, eq, isNull, sql } from 'drizzle-orm'
import { z } from 'zod'
import type { ActionResult } from '@florin/core/types'
import type { PgDB } from '../client'
import { transactions } from '../schema'
import { recomputeAccountBalance } from './helpers'

// Reconciliation: when bank sync imports a transaction, it may duplicate an
// existing scheduled (forecast) or recent manual row. We fuzzily match and
// surface a *suggestion* (never auto-merge) in the Review queue.

/** Amounts must match to the cent. */
const MERGE_AMOUNT_EPSILON = 0.01
/** Booking vs value date drift, and day-2 DCA settling on day-3, etc. */
const MERGE_WINDOW_DAYS = 3

/**
 * Find the best merge candidate for an incoming bank transaction on the same
 * account: a scheduled row, or a recent manual cleared row, with the same sign,
 * amount within one cent, and occurredAt within ±3 days. Returns the candidate
 * id (best by amountDiff then dateDiff) or null. Rows that already carry an
 * externalId (i.e. are themselves bank rows) are never candidates.
 */
export async function findMergeCandidateId(
  db: PgDB,
  bank: { accountId: string; amount: number; occurredAt: Date; excludeId?: string },
): Promise<string | null> {
  const rows = await db
    .select({
      id: transactions.id,
      amount: transactions.amount,
      occurredAt: transactions.occurredAt,
    })
    .from(transactions)
    .where(
      and(
        eq(transactions.accountId, bank.accountId),
        isNull(transactions.deletedAt),
        isNull(transactions.externalId),
        sql`(${transactions.status} = 'scheduled' OR (${transactions.status} = 'cleared' AND ${transactions.source} = 'manual'))`,
      ),
    )

  const bankTime = bank.occurredAt.getTime()
  let best: { id: string; amountDiff: number; dateDiff: number } | null = null
  for (const c of rows) {
    if (bank.excludeId && c.id === bank.excludeId) continue
    const amt = Number(c.amount)
    if (!Number.isFinite(amt) || amt === 0) continue
    if (Math.sign(amt) !== Math.sign(bank.amount)) continue
    const amountDiff = Math.abs(amt - bank.amount)
    if (amountDiff > MERGE_AMOUNT_EPSILON) continue
    const dateDiff = Math.abs(c.occurredAt.getTime() - bankTime) / 86_400_000
    if (dateDiff > MERGE_WINDOW_DAYS) continue
    if (
      !best ||
      amountDiff < best.amountDiff ||
      (amountDiff === best.amountDiff && dateDiff < best.dateDiff)
    ) {
      best = { id: c.id, amountDiff, dateDiff }
    }
  }
  return best?.id ?? null
}

const mergeSchema = z.object({ bankTxId: z.uuid(), candidateTxId: z.uuid() })

/**
 * Accept a merge suggestion. The candidate absorbs the bank row's identity
 * (source + externalId + rawData + the real bank date) and becomes cleared,
 * keeping its own links (transferPairId, recurringRuleId, category). The
 * duplicate bank row is then hard-deleted so the (source, externalId) unique
 * slot is held by the candidate — future syncs conflict-skip instead of
 * re-creating the duplicate.
 */
export async function mergeBankTransactionMutation(
  db: PgDB,
  bankTxId: string,
  candidateTxId: string,
): Promise<ActionResult> {
  const parsed = mergeSchema.safeParse({ bankTxId, candidateTxId })
  if (!parsed.success) return { success: false, error: 'Invalid transaction id' }
  if (bankTxId === candidateTxId) return { success: false, error: 'Cannot merge a row with itself' }
  try {
    const bank = await db.query.transactions.findFirst({ where: eq(transactions.id, bankTxId) })
    const candidate = await db.query.transactions.findFirst({
      where: eq(transactions.id, candidateTxId),
    })
    if (!bank || !candidate) return { success: false, error: 'Transaction not found' }

    // Delete the bank row FIRST so the candidate can take over its
    // (source, externalId) slot without colliding on the unique index.
    await db.delete(transactions).where(eq(transactions.id, bankTxId))

    await db
      .update(transactions)
      .set({
        status: 'cleared',
        source: bank.source,
        externalId: bank.externalId,
        rawData: bank.rawData,
        occurredAt: bank.occurredAt,
        needsReview: false,
        mergeSuggestedTxId: null,
        updatedAt: new Date(),
      })
      .where(eq(transactions.id, candidateTxId))

    if (candidate.accountId) await recomputeAccountBalance(db, candidate.accountId)
    if (bank.accountId && bank.accountId !== candidate.accountId) {
      await recomputeAccountBalance(db, bank.accountId)
    }
    return { success: true }
  } catch (error: unknown) {
    return { success: false, error: error instanceof Error ? error.message : 'Failed to merge' }
  }
}

/** Dismiss a merge suggestion (keep both rows); just clears the link. */
export async function dismissMergeSuggestionMutation(
  db: PgDB,
  bankTxId: string,
): Promise<ActionResult> {
  const parsed = z.uuid().safeParse(bankTxId)
  if (!parsed.success) return { success: false, error: 'Invalid transaction id' }
  try {
    await db
      .update(transactions)
      .set({ mergeSuggestedTxId: null, updatedAt: new Date() })
      .where(eq(transactions.id, bankTxId))
    return { success: true }
  } catch (error: unknown) {
    return { success: false, error: error instanceof Error ? error.message : 'Failed to dismiss' }
  }
}
