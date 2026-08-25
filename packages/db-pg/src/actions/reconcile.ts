import { and, eq, isNull, sql } from 'drizzle-orm'
import { z } from 'zod'
import { isPlaceholderOf } from '@florin/core/lib/reconcile'
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
 * A bank re-booking its own provisional entry takes longer than a date
 * drift: observed at one and two days on LBP, and a weekend can stretch it.
 */
const REBOOKING_WINDOW_DAYS = 5

/**
 * Find the best merge candidate for an incoming bank transaction on the same
 * account, in either of two shapes.
 *
 * **A row the user already knew about** — a scheduled forecast or a recent
 * manual entry — with the same sign, amount within one cent and occurredAt
 * within ±3 days.
 *
 * **The bank's own earlier booking of this very transaction** — a previously
 * imported bank row, dated up to five days *before* this one, whose label is a
 * placeholder the incoming label enriches (see `isPlaceholderOf`). Without this
 * arm, a bank that re-books instant transfers under a fresh positional
 * reference silently doubles them: the unique index is `(source, external_id)`
 * and the reference is new, so nothing conflicts.
 *
 * Returns the candidate id (best by amountDiff then dateDiff) or null. Never
 * merges anything on its own — the caller records a suggestion for the Review
 * queue, because two identical transfers days apart are a real thing that
 * arithmetic cannot tell from a re-booking.
 */
export async function findMergeCandidateId(
  db: PgDB,
  bank: {
    accountId: string
    amount: number
    occurredAt: Date
    /** The incoming label, for the re-booking test. */
    payee?: string
    excludeId?: string
  },
): Promise<string | null> {
  const rows = await db
    .select({
      id: transactions.id,
      amount: transactions.amount,
      occurredAt: transactions.occurredAt,
      payee: transactions.payee,
      externalId: transactions.externalId,
    })
    .from(transactions)
    .where(
      and(
        eq(transactions.accountId, bank.accountId),
        isNull(transactions.deletedAt),
        sql`(
          (${transactions.externalId} IS NULL AND (
            ${transactions.status} = 'scheduled'
            OR (${transactions.status} = 'cleared' AND ${transactions.source} = 'manual'
                AND ${transactions.occurredAt}::date >= CURRENT_DATE - INTERVAL '14 days')
          ))
          OR (${transactions.externalId} IS NOT NULL
              AND ${transactions.occurredAt}::date >= CURRENT_DATE - INTERVAL '90 days')
        )`,
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
    if (c.externalId) {
      // The bank's own earlier booking: it must come *first*, and its label
      // must be the one this row enriches.
      if (c.occurredAt.getTime() > bankTime) continue
      if (dateDiff > REBOOKING_WINDOW_DAYS) continue
      if (!bank.payee || !isPlaceholderOf(c.payee ?? '', bank.payee)) continue
    } else if (dateDiff > MERGE_WINDOW_DAYS) {
      continue
    }
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

    /*
     * Two shapes of merge, and they keep different rows.
     *
     * Against a scheduled or manual row, the *candidate* survives: it carries
     * the user's own category, its transfer pairing and its recurring rule, and
     * it absorbs the bank row's identity so future syncs conflict-skip.
     *
     * Against the bank's own earlier booking, the *incoming* row survives
     * instead — it is the one holding the counterparty ("VIREMENT INSTANTANE DE
     * MME ROBINO AGNES" rather than "VIREMENT INSTANTANE CREDIT"). Keeping the
     * placeholder here would throw away the only thing the second booking added.
     * The category still moves across when the survivor has none of its own.
     */
    if (candidate.externalId) {
      await db.transaction(async (tx) => {
        if (!bank.categoryId && candidate.categoryId) {
          await tx
            .update(transactions)
            .set({ categoryId: candidate.categoryId, updatedAt: new Date() })
            .where(eq(transactions.id, bankTxId))
        }
        await tx
          .update(transactions)
          .set({ mergeSuggestedTxId: null, updatedAt: new Date() })
          .where(eq(transactions.id, bankTxId))
        // Soft delete: every query filters on deletedAt, and a bank re-booking
        // is exactly the kind of call worth being able to walk back.
        await tx
          .update(transactions)
          .set({ deletedAt: new Date(), updatedAt: new Date() })
          .where(eq(transactions.id, candidateTxId))
      })

      if (bank.accountId) await recomputeAccountBalance(db, bank.accountId)
      return { success: true }
    }

    // Delete the bank row FIRST so the candidate can take over its
    // (source, externalId) slot without colliding on the unique index. Both
    // steps run in one transaction so a partial failure can't strand the
    // candidate as 'scheduled' with the bank row already gone.
    await db.transaction(async (tx) => {
      await tx.delete(transactions).where(eq(transactions.id, bankTxId))
      await tx
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
    })

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
