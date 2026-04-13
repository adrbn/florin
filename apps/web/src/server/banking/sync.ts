/**
 * Bank sync — pulls accounts, balances, and transactions from Enable Banking
 * for one bank_connections row, and merges them into Florin's tables.
 *
 * Design constraints:
 *   1. **Idempotent.** Re-running a sync must not duplicate transactions. We
 *      lean on the unique index `transactions_source_external_unique` on
 *      `(source, external_id)` and use INSERT ... ON CONFLICT DO NOTHING.
 *   2. **No partial corruption.** Each account is synced independently — if
 *      one fails (e.g. bank rate-limits), the others still complete and the
 *      error gets recorded on bank_connections.lastSyncError so the UI can
 *      show it without faking a green status.
 *   3. **Auto-link new accounts.** The first sync after a consent will not
 *      have any matching Florin accounts yet — we create one per remote
 *      account UID, defaulting kind='checking' and currency from the bank.
 *      The user can edit kind/name afterwards via the existing edit form.
 *   4. **Categorize on insert.** New transactions go through the existing
 *      rule engine so they land already classified when possible.
 */
import { and, desc, eq, isNotNull, isNull } from 'drizzle-orm'
import { db } from '@/db/client'
import {
  accounts,
  bankConnections,
  categorizationRules,
  type NewTransaction,
  transactions,
} from '@/db/schema'
import { matchRule, type Rule } from '@/lib/categorization/engine'
import { normalizePayee } from '@/lib/categorization/normalize-payee'
import { getAccountDetails, getBalances, getSession, getTransactions } from './enable-banking'
import type { AccountDetails, BankTransaction } from './types'

export interface SyncResult {
  connectionId: string
  accountsSynced: number
  transactionsInserted: number
  errors: ReadonlyArray<{ accountUid: string; message: string }>
  durationMs: number
}

/**
 * PSD2 caps unattended transaction history at 90 days — going further back
 * requires a fresh SCA and extra consent flags that vary per bank. LBP (and
 * most French banks) simply refuse anything older with 422
 * WRONG_TRANSACTIONS_PERIOD, so we pin to 90 days for both first and
 * subsequent syncs. Older history lives in the legacy XLSX import.
 */
const TX_LOOKBACK_DAYS = 90
const TX_LOOKBACK_DAYS_INITIAL = 90

function isoDate(d: Date): string {
  return d.toISOString().slice(0, 10)
}

function pickPayee(t: BankTransaction): string {
  // Banks return remittance information in 3-4 different shapes — we walk the
  // common ones in priority order so we always have something usable.
  if (t.creditor?.name) return t.creditor.name
  if (t.debtor?.name) return t.debtor.name
  if (t.remittance_information_unstructured) return t.remittance_information_unstructured
  if (t.remittance_information && t.remittance_information.length > 0) {
    return t.remittance_information.join(' ').trim()
  }
  return t.bank_transaction_code?.description ?? '(unknown)'
}

function pickOccurredAt(t: BankTransaction): Date {
  // Prefer value_date (economic effect) over booking_date (when bank recorded
  // it). Fall back to today if both missing — should not happen but some
  // banks return junk.
  const raw = t.value_date ?? t.booking_date
  if (!raw) return new Date()
  const parsed = new Date(raw)
  return Number.isNaN(parsed.getTime()) ? new Date() : parsed
}

function signedAmount(t: BankTransaction): string {
  // Enable Banking returns amount as a positive string + a separate
  // CRDT/DBIT indicator. We canonicalize to a signed decimal because the rest
  // of Florin (and the unique index) treats amount as signed.
  const raw = t.transaction_amount.amount
  const isDebit = t.credit_debit_indicator === 'DBIT'
  if (raw.startsWith('-') || raw.startsWith('+')) return raw // already signed
  return isDebit ? `-${raw}` : raw
}

async function ensureAccountForUid(
  connectionId: string,
  uid: string,
  details: AccountDetails,
  aspspName: string,
): Promise<string> {
  const existing = await db.query.accounts.findFirst({
    where: and(eq(accounts.syncProvider, 'enable_banking'), eq(accounts.syncExternalId, uid)),
  })
  if (existing) {
    // Re-bind to current connection in case the user re-authorized.
    if (existing.bankConnectionId !== connectionId) {
      await db
        .update(accounts)
        .set({ bankConnectionId: connectionId, updatedAt: new Date() })
        .where(eq(accounts.id, existing.id))
    }
    return existing.id
  }
  // Prefer the product name (e.g. "CCP", "Livret A") over `details.name`,
  // which on several French banks (LBP, Crédit Agricole, …) is the holder's
  // legal name in caps — almost never what the user wants to see in the
  // sidebar. Fall back to a "{Bank} ·{last 4 of IBAN}" tag if the bank
  // doesn't expose a product label, then to the IBAN itself.
  const ibanTail = details.account_id?.iban?.slice(-4)
  const defaultName =
    details.product ??
    (ibanTail ? `${aspspName} ·${ibanTail}` : null) ??
    details.account_id?.iban ??
    details.name ??
    'Bank account'
  const inserted = await db
    .insert(accounts)
    .values({
      name: defaultName,
      kind: 'checking',
      institution: aspspName,
      currency: details.currency,
      iban: details.account_id?.iban ?? null,
      isIncludedInNetWorth: true,
      syncProvider: 'enable_banking',
      syncExternalId: uid,
      bankConnectionId: connectionId,
    })
    .returning({ id: accounts.id })
  const newId = inserted[0]?.id
  if (!newId) {
    throw new Error(`Failed to insert account for remote uid ${uid}`)
  }
  return newId
}

async function syncAccountTransactions(
  florinAccountId: string,
  remoteUid: string,
  isFirstSync: boolean,
  rules: ReadonlyArray<Rule>,
  syncStartDate: Date,
): Promise<number> {
  const lookbackDays = isFirstSync ? TX_LOOKBACK_DAYS_INITIAL : TX_LOOKBACK_DAYS
  const dateTo = new Date()
  // Floor at (today - 90d) because PSD2 refuses anything older.
  const psd2Floor = new Date(Date.now() - lookbackDays * 24 * 60 * 60 * 1000)

  // Per-account watermark — pick up the day AFTER the latest existing
  // transaction on this account, regardless of source. This is what makes
  // bank data slot in cleanly behind legacy XLSX history without
  // duplicating overlapping days. Falls back to the connection's
  // syncStartDate when the account has no transactions yet (e.g. brand
  // new connection on a fresh Florin install).
  const latestExisting = await db.query.transactions.findFirst({
    where: and(eq(transactions.accountId, florinAccountId), isNull(transactions.deletedAt)),
    orderBy: [desc(transactions.occurredAt)],
  })
  const accountWatermark = latestExisting
    ? new Date(latestExisting.occurredAt.getTime() + 24 * 60 * 60 * 1000)
    : syncStartDate

  // Pick the most-recent of (per-account watermark, PSD2 floor). PSD2
  // wins when the account hasn't been touched in over 90 days because the
  // bank simply won't return anything older than that.
  const dateFrom = accountWatermark > psd2Floor ? accountWatermark : psd2Floor
  // Guard: if the watermark is in the future (e.g. user reset to "today"
  // and then re-ran the sync a minute later), bail out with 0 new rows.
  if (dateFrom > dateTo) return 0
  let inserted = 0
  let continuationKey: string | undefined

  do {
    const page = await getTransactions(remoteUid, {
      dateFrom: isoDate(dateFrom),
      dateTo: isoDate(dateTo),
      continuationKey,
    })
    const rows: NewTransaction[] = page.transactions
      .filter((t) => Boolean(t.transaction_id ?? t.entry_reference))
      .map((t): NewTransaction => {
        const payee = pickPayee(t)
        const normalizedPayee = normalizePayee(payee)
        const amount = signedAmount(t)
        const externalId = t.transaction_id ?? t.entry_reference ?? null
        const categoryId = matchRule(
          { payee: normalizedPayee, amount: Number(amount), accountId: florinAccountId },
          rules,
        )
        return {
          accountId: florinAccountId,
          occurredAt: pickOccurredAt(t),
          amount,
          currency: t.transaction_amount.currency,
          payee,
          normalizedPayee,
          memo: t.note ?? null,
          categoryId,
          source: 'enable_banking',
          externalId,
          isPending: t.status === 'PDNG',
          // Bank-imported rows land in the review queue. The user explicitly
          // wants a YNAB-style "approve before it counts" workflow so we
          // never auto-trust the bank's payee text or our own rule guess.
          needsReview: true,
          rawData: JSON.stringify(t),
        }
      })

    if (rows.length > 0) {
      const result = await db.insert(transactions).values(rows).onConflictDoNothing().returning({
        id: transactions.id,
      })
      inserted += result.length
    }

    continuationKey = page.continuation_key
  } while (continuationKey)

  return inserted
}

async function syncAccountBalance(florinAccountId: string, remoteUid: string): Promise<void> {
  const { balances } = await getBalances(remoteUid)
  // Pick the freshest balance type the bank exposes.
  //   ITAV = interim available      → includes today's activity (real-time)
  //   XPCD = expected                → interim + pending authorizations
  //   CLAV = closing available       → end-of-day, spendable
  //   ITBD = interim booked          → today's booked side
  //   CLBD = closing booked          → LBP returns YESTERDAY's booked
  // LBP specifically lags on CLBD: transactions from today land in
  // Prefer booked balances (actual funds) over available balances (which
  // include overdraft/credit facilities and overstate the real balance).
  // ITBD is still real-time but without the overdraft inflation.
  const preference = ['CLBD', 'ITBD', 'XPCD', 'CLAV', 'ITAV'] as const
  const closing =
    preference.map((t) => balances.find((b) => b.balance_type === t)).find(Boolean) ?? balances[0]
  if (!closing) return
  await db
    .update(accounts)
    .set({
      currentBalance: closing.balance_amount.amount,
      lastSyncedAt: new Date(),
      updatedAt: new Date(),
    })
    .where(eq(accounts.id, florinAccountId))
}

async function loadActiveRules(): Promise<ReadonlyArray<Rule>> {
  const rows = await db
    .select()
    .from(categorizationRules)
    .where(eq(categorizationRules.isActive, true))
  return rows.map(
    (r): Rule => ({
      id: r.id,
      priority: r.priority,
      categoryId: r.categoryId,
      isActive: r.isActive,
      matchPayeeRegex: r.matchPayeeRegex,
      matchMinAmount: r.matchMinAmount === null ? null : Number(r.matchMinAmount),
      matchMaxAmount: r.matchMaxAmount === null ? null : Number(r.matchMaxAmount),
      matchAccountId: r.matchAccountId,
    }),
  )
}

/**
 * Sync one bank connection end-to-end. Idempotent — safe to call repeatedly.
 * Returns counts and per-account errors instead of throwing on partial failure.
 */
export async function syncConnection(connectionId: string): Promise<SyncResult> {
  const startedAt = Date.now()
  const connection = await db.query.bankConnections.findFirst({
    where: eq(bankConnections.id, connectionId),
  })
  if (!connection) {
    throw new Error(`Bank connection ${connectionId} not found`)
  }

  const session = await getSession(connection.sessionId)
  if (session.status !== 'AUTHORIZED') {
    await db
      .update(bankConnections)
      .set({
        status: session.status === 'EXPIRED' ? 'expired' : 'revoked',
        lastSyncError: `Session is ${session.status} — re-authentication required`,
        updatedAt: new Date(),
      })
      .where(eq(bankConnections.id, connectionId))
    return {
      connectionId,
      accountsSynced: 0,
      transactionsInserted: 0,
      errors: [{ accountUid: '*', message: `Session ${session.status}` }],
      durationMs: Date.now() - startedAt,
    }
  }

  const rules = await loadActiveRules()
  const errors: { accountUid: string; message: string }[] = []
  let totalInserted = 0
  let accountsSynced = 0

  for (const uid of session.accounts) {
    try {
      // Enable Banking returns a list of UIDs — we have to hit
      // /accounts/{uid}/details to get the name, IBAN, currency, etc.
      const details = await getAccountDetails(uid)
      const florinAccountId = await ensureAccountForUid(
        connectionId,
        uid,
        details,
        connection.aspspName,
      )
      // Detect first sync by absence of any prior transaction for this account.
      const priorTx = await db.query.transactions.findFirst({
        where: and(
          eq(transactions.accountId, florinAccountId),
          eq(transactions.source, 'enable_banking'),
          isNotNull(transactions.externalId),
          isNull(transactions.deletedAt),
        ),
      })
      const isFirstSync = !priorTx
      await syncAccountBalance(florinAccountId, uid)
      const inserted = await syncAccountTransactions(
        florinAccountId,
        uid,
        isFirstSync,
        rules,
        connection.syncStartDate,
      )
      totalInserted += inserted
      accountsSynced += 1
    } catch (error: unknown) {
      const message = error instanceof Error ? error.message : 'unknown error'
      errors.push({ accountUid: uid, message })
    }
  }

  await db
    .update(bankConnections)
    .set({
      lastSyncedAt: new Date(),
      lastSyncError: errors.length > 0 ? errors.map((e) => e.message).join('; ') : null,
      updatedAt: new Date(),
    })
    .where(eq(bankConnections.id, connectionId))

  return {
    connectionId,
    accountsSynced,
    transactionsInserted: totalInserted,
    errors,
    durationMs: Date.now() - startedAt,
  }
}
