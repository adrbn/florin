import { and, eq, isNull, sql } from 'drizzle-orm'
import { z } from 'zod'
import { isPlaceholderOf } from '@florin/core/lib/reconcile'
import type { ActionResult } from '@florin/core/types'
import type { SqliteDB } from '../client'
import { transactions } from '../schema'
import { recomputeAccountBalance } from './helpers'

// SQLite twin of db-pg/reconcile.ts. occurredAt is an ISO 'YYYY-MM-DD' string.

const MERGE_AMOUNT_EPSILON = 0.01
const MERGE_WINDOW_DAYS = 3
/**
 * A bank re-booking its own provisional entry takes longer than a date
 * drift: observed at one and two days on LBP, and a weekend can stretch it.
 */
const REBOOKING_WINDOW_DAYS = 5

function dayMs(iso: string): number {
  const t = new Date(`${iso.slice(0, 10)}T00:00:00Z`).getTime()
  return Number.isNaN(t) ? Number.NaN : t
}

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
  db: SqliteDB,
  bank: {
    accountId: string
    amount: number
    occurredAt: string
    /** The incoming label, for the re-booking test. */
    payee?: string
    excludeId?: string
  },
): Promise<string | null> {
  const cutoffIso = new Date(Date.now() - 14 * 86_400_000).toISOString().slice(0, 10)
  const bankCutoffIso = new Date(Date.now() - 90 * 86_400_000).toISOString().slice(0, 10)
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
                AND ${transactions.occurredAt} >= ${cutoffIso})
          ))
          OR (${transactions.externalId} IS NOT NULL AND ${transactions.occurredAt} >= ${bankCutoffIso})
        )`,
      ),
    )

  const bankTime = dayMs(bank.occurredAt)
  if (Number.isNaN(bankTime)) return null
  let best: { id: string; amountDiff: number; dateDiff: number } | null = null
  for (const c of rows) {
    if (bank.excludeId && c.id === bank.excludeId) continue
    const amt = Number(c.amount)
    if (!Number.isFinite(amt) || amt === 0) continue
    if (Math.sign(amt) !== Math.sign(bank.amount)) continue
    const amountDiff = Math.abs(amt - bank.amount)
    if (amountDiff > MERGE_AMOUNT_EPSILON) continue
    const cTime = dayMs(c.occurredAt)
    if (Number.isNaN(cTime)) continue
    const dateDiff = Math.abs(cTime - bankTime) / 86_400_000
    if (c.externalId) {
      // The bank's own earlier booking: it must come *first*, and its label
      // must be the one this row enriches.
      if (cTime > bankTime) continue
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

export async function mergeBankTransactionMutation(
  db: SqliteDB,
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
            .set({ categoryId: candidate.categoryId, updatedAt: new Date().toISOString() })
            .where(eq(transactions.id, bankTxId))
        }
        await tx
          .update(transactions)
          .set({ mergeSuggestedTxId: null, updatedAt: new Date().toISOString() })
          .where(eq(transactions.id, bankTxId))
        // Soft delete: every query filters on deletedAt, and a bank re-booking
        // is exactly the kind of call worth being able to walk back.
        await tx
          .update(transactions)
          .set({ deletedAt: new Date().toISOString(), updatedAt: new Date().toISOString() })
          .where(eq(transactions.id, candidateTxId))
      })

      if (bank.accountId) await recomputeAccountBalance(db, bank.accountId)
      return { success: true }
    }


    // Both steps in one (synchronous) better-sqlite3 transaction so a partial
    // failure can't strand the candidate as 'scheduled' with the bank row gone.
    db.transaction((tx) => {
      tx.delete(transactions).where(eq(transactions.id, bankTxId)).run()
      tx
        .update(transactions)
        .set({
          status: 'cleared',
          source: bank.source,
          externalId: bank.externalId,
          rawData: bank.rawData,
          occurredAt: bank.occurredAt,
          needsReview: false,
          mergeSuggestedTxId: null,
          updatedAt: new Date().toISOString(),
        })
        .where(eq(transactions.id, candidateTxId))
        .run()
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

export async function dismissMergeSuggestionMutation(
  db: SqliteDB,
  bankTxId: string,
): Promise<ActionResult> {
  const parsed = z.uuid().safeParse(bankTxId)
  if (!parsed.success) return { success: false, error: 'Invalid transaction id' }
  try {
    await db
      .update(transactions)
      .set({ mergeSuggestedTxId: null, updatedAt: new Date().toISOString() })
      .where(eq(transactions.id, bankTxId))
    return { success: true }
  } catch (error: unknown) {
    return { success: false, error: error instanceof Error ? error.message : 'Failed to dismiss' }
  }
}
