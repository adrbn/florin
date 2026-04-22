import { randomUUID } from 'node:crypto'
import { and, eq, isNull, sql } from 'drizzle-orm'
import { normalizePayee } from '@florin/core/lib/categorization'
import type { PgDB } from '../client'
import { accounts, categories, transactions } from '../schema'

/**
 * Recompute an account's currentBalance from the sum of its non-deleted
 * transactions. Called after inserts, updates, and deletes so the headline
 * balance stays in sync with the transaction ledger.
 *
 * IMPORTANT: accounts whose balance is *authoritative from somewhere other than
 * the local ledger* are skipped here:
 *   - `enable_banking` / `pytr`: balance comes from the sync API, and the
 *     local ledger only holds a truncated window (PSD2 caps at 90 days).
 *   - `legacy`: balance was set manually at import time from an external
 *     source (XLSX, YNAB, …) so the local ledger is a partial snapshot.
 * Summing the partial ledger for any of those clobbers the real value — a
 * Livret A showing ~3000€ dropped to -372€ after a local internal-transfer
 * shadow added onto the truncated ledger.
 *
 * For those skipped accounts, callers that genuinely need to move the
 * balance (e.g. a transfer shadow leg adds +100€ of real money) should pass
 * `delta` — we apply it directly to `currentBalance` instead of recomputing.
 */
const SKIP_RECOMPUTE_PROVIDERS: ReadonlySet<string> = new Set([
  'enable_banking',
  'pytr',
  'legacy',
])

export async function recomputeAccountBalance(
  db: PgDB,
  accountId: string,
  delta?: number,
): Promise<void> {
  const acc = await db.query.accounts.findFirst({
    where: eq(accounts.id, accountId),
    columns: { syncProvider: true },
  })
  if (!acc) return
  if (acc.syncProvider && SKIP_RECOMPUTE_PROVIDERS.has(acc.syncProvider)) {
    if (delta && delta !== 0) {
      await db
        .update(accounts)
        .set({
          currentBalance: sql`${accounts.currentBalance}::numeric + ${delta.toFixed(2)}::numeric`,
          updatedAt: new Date(),
        })
        .where(eq(accounts.id, accountId))
    }
    return
  }

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

/**
 * Reconcile the loan-mirror transaction for a given original transaction.
 *
 * A "loan mirror" is a paired, auto-generated row on a loan-kind account
 * that represents "this payment reduced the loan balance". Triggered when
 * the original transaction is categorized into a category whose
 * `linkedLoanAccountId` points at a loan account.
 */
export async function syncLoanMirror(db: PgDB, transactionId: string): Promise<void> {
  const original = await db.query.transactions.findFirst({
    where: eq(transactions.id, transactionId),
  })
  if (!original || !original.accountId) return

  const originalAccount = await db.query.accounts.findFirst({
    where: eq(accounts.id, original.accountId),
  })
  if (!originalAccount) return
  if (originalAccount.kind === 'loan') return

  let linkedLoanAccountId: string | null = null
  if (original.categoryId) {
    const cat = await db.query.categories.findFirst({
      where: eq(categories.id, original.categoryId),
    })
    linkedLoanAccountId = cat?.linkedLoanAccountId ?? null
  }

  const touchedLoanAccountIds = new Set<string>()
  let existingMirror: typeof original | null = null
  if (original.transferPairId) {
    const pair = await db.query.transactions.findFirst({
      where: and(
        eq(transactions.transferPairId, original.transferPairId),
        sql`${transactions.id} <> ${original.id}`,
      ),
    })
    existingMirror = pair ?? null
    if (existingMirror?.accountId) touchedLoanAccountIds.add(existingMirror.accountId)
  }

  // Case 1: no link
  if (!linkedLoanAccountId) {
    if (existingMirror) {
      await db.delete(transactions).where(eq(transactions.id, existingMirror.id))
    }
    if (original.transferPairId) {
      await db
        .update(transactions)
        .set({ transferPairId: null, updatedAt: new Date() })
        .where(eq(transactions.id, original.id))
    }
    for (const id of touchedLoanAccountIds) await recomputeAccountBalance(db, id)
    return
  }

  // Case 2: mirror on wrong loan
  if (existingMirror && existingMirror.accountId !== linkedLoanAccountId) {
    await db.delete(transactions).where(eq(transactions.id, existingMirror.id))
    existingMirror = null
  }

  const mirrorAmount = (-Number(original.amount)).toFixed(2)
  const mirrorPayee = `\u21b3 ${original.payee || '(no payee)'}`

  if (!existingMirror) {
    // Case 3: create fresh mirror
    const pairId = original.transferPairId ?? randomUUID()
    await db.insert(transactions).values({
      accountId: linkedLoanAccountId,
      occurredAt: original.occurredAt,
      amount: mirrorAmount,
      currency: original.currency,
      payee: mirrorPayee,
      normalizedPayee: normalizePayee(mirrorPayee),
      memo: 'auto: loan payment mirror',
      categoryId: null,
      source: 'manual',
      transferPairId: pairId,
      needsReview: false,
    })
    if (original.transferPairId !== pairId) {
      await db
        .update(transactions)
        .set({ transferPairId: pairId, updatedAt: new Date() })
        .where(eq(transactions.id, original.id))
    }
    touchedLoanAccountIds.add(linkedLoanAccountId)
  } else {
    // Case 4: update existing mirror
    await db
      .update(transactions)
      .set({
        occurredAt: original.occurredAt,
        amount: mirrorAmount,
        payee: mirrorPayee,
        normalizedPayee: normalizePayee(mirrorPayee),
        updatedAt: new Date(),
      })
      .where(eq(transactions.id, existingMirror.id))
    touchedLoanAccountIds.add(linkedLoanAccountId)
  }

  for (const id of touchedLoanAccountIds) await recomputeAccountBalance(db, id)
}

/**
 * When an original transaction is being deleted, remove its loan mirror
 * first so we don't leave an orphan row on the loan account.
 */
export async function deleteLoanMirrorFor(
  db: PgDB,
  transactionId: string,
): Promise<ReadonlyArray<string>> {
  const original = await db.query.transactions.findFirst({
    where: eq(transactions.id, transactionId),
  })
  if (!original || !original.transferPairId) return []
  const pair = await db.query.transactions.findFirst({
    where: and(
      eq(transactions.transferPairId, original.transferPairId),
      sql`${transactions.id} <> ${original.id}`,
    ),
  })
  if (!pair) return []
  await db.delete(transactions).where(eq(transactions.id, pair.id))
  return pair.accountId ? [pair.accountId] : []
}

/**
 * Walk every non-deleted transaction in `categoryId` and re-run loan-mirror
 * reconciliation. Used when a category -> loan link is first set.
 */
export async function reconcileLoanMirrorsForCategory(
  db: PgDB,
  categoryId: string,
): Promise<number> {
  const rows = await db
    .select({ id: transactions.id })
    .from(transactions)
    .where(and(eq(transactions.categoryId, categoryId), isNull(transactions.deletedAt)))
  for (const row of rows) {
    await syncLoanMirror(db, row.id)
  }
  return rows.length
}
