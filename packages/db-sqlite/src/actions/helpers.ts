import { randomUUID } from 'node:crypto'
import { and, eq, isNull, sql } from 'drizzle-orm'
import { normalizePayee } from '@florin/core/lib/categorization'
import type { SqliteDB } from '../client'
import { accounts, categories, transactions } from '../schema'

/**
 * Recompute an account's currentBalance from the sum of its non-deleted
 * transactions. Called after inserts, updates, and deletes so the headline
 * balance stays in sync with the transaction ledger.
 *
 * IMPORTANT: Bank-synced accounts (`syncProvider` = 'enable_banking' | 'pytr')
 * are skipped. Their authoritative balance comes from the sync API — PSD2
 * only exposes the last 90 days of transactions, so the ledger sum is almost
 * always incomplete. Overwriting `currentBalance` with that partial sum
 * destroyed real balances (e.g. a Livret A showing ~3000€ dropped to -372€
 * after a local internal-transfer shadow got added to its truncated ledger).
 */
export async function recomputeAccountBalance(db: SqliteDB, accountId: string): Promise<void> {
  const acc = await db.query.accounts.findFirst({
    where: eq(accounts.id, accountId),
    columns: { syncProvider: true },
  })
  if (!acc) return
  if (acc.syncProvider === 'enable_banking' || acc.syncProvider === 'pytr') return

  const result = await db
    .select({
      total: sql<number>`COALESCE(SUM(${transactions.amount}), 0)`,
    })
    .from(transactions)
    .where(and(eq(transactions.accountId, accountId), isNull(transactions.deletedAt)))

  const total = result[0]?.total ?? 0
  await db
    .update(accounts)
    .set({ currentBalance: total, updatedAt: new Date().toISOString() })
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
export async function syncLoanMirror(db: SqliteDB, transactionId: string): Promise<void> {
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
        .set({ transferPairId: null, updatedAt: new Date().toISOString() })
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

  const mirrorAmount = -Number(original.amount)
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
        .set({ transferPairId: pairId, updatedAt: new Date().toISOString() })
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
        updatedAt: new Date().toISOString(),
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
  db: SqliteDB,
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
  db: SqliteDB,
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
