import { and, eq, isNull, sql } from 'drizzle-orm'
import { z } from 'zod'
import type { ActionResult } from '@florin/core/types'
import type { SqliteDB } from '../client'
import { transactions } from '../schema'
import { recomputeAccountBalance } from './helpers'

// SQLite twin of db-pg/reconcile.ts. occurredAt is an ISO 'YYYY-MM-DD' string.

const MERGE_AMOUNT_EPSILON = 0.01
const MERGE_WINDOW_DAYS = 3

function dayMs(iso: string): number {
  const t = new Date(`${iso.slice(0, 10)}T00:00:00Z`).getTime()
  return Number.isNaN(t) ? Number.NaN : t
}

/**
 * Find the best merge candidate for an incoming bank transaction. See the
 * db-pg twin for semantics. `occurredAt` is an ISO date string here.
 */
export async function findMergeCandidateId(
  db: SqliteDB,
  bank: { accountId: string; amount: number; occurredAt: string; excludeId?: string },
): Promise<string | null> {
  const cutoffIso = new Date(Date.now() - 14 * 86_400_000).toISOString().slice(0, 10)
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
        // Candidates: any scheduled row, OR a RECENT manual cleared row (last
        // 14 days) — so an old manual entry can't be matched to a same-amount
        // bank row that merely shares a date.
        sql`(${transactions.status} = 'scheduled' OR (${transactions.status} = 'cleared' AND ${transactions.source} = 'manual' AND ${transactions.occurredAt} >= ${cutoffIso}))`,
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
