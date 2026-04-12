/**
 * Bank sync — pulls accounts, balances, and transactions from Enable Banking
 * for one bank_connections row, and merges them into Florin's SQLite tables.
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
import {
  type EnableBankingConfig,
  getAccountDetails,
  getBalances,
  getSession,
  getTransactions,
} from '@florin/core/banking'
import type { AccountDetails, BankTransaction } from '@florin/core/banking'
import { matchRule, type Rule, normalizePayee } from '@florin/core/lib/categorization'
import { db } from '@/db/client'
import {
  accounts,
  bankConnections,
  categorizationRules,
  type NewTransaction,
  transactions,
} from '@/db/schema'
import { getEnableBankingConfig } from './config'

export interface SyncResult {
  connectionId: string
  accountsSynced: number
  transactionsInserted: number
  errors: ReadonlyArray<{ accountUid: string; message: string }>
  durationMs: number
}

/**
 * PSD2 caps unattended transaction history at 90 days — going further back
 * requires a fresh SCA and extra consent flags that vary per bank.
 */
const TX_LOOKBACK_DAYS = 90
const TX_LOOKBACK_DAYS_INITIAL = 90

function isoDate(d: Date): string {
  return d.toISOString().slice(0, 10)
}

function pickPayee(t: BankTransaction): string {
  if (t.creditor?.name) return t.creditor.name
  if (t.debtor?.name) return t.debtor.name
  if (t.remittance_information_unstructured) return t.remittance_information_unstructured
  if (t.remittance_information && t.remittance_information.length > 0) {
    return t.remittance_information.join(' ').trim()
  }
  return t.bank_transaction_code?.description ?? '(unknown)'
}

function pickOccurredAt(t: BankTransaction): string {
  const raw = t.value_date ?? t.booking_date
  if (!raw) return new Date().toISOString()
  const parsed = new Date(raw)
  return Number.isNaN(parsed.getTime()) ? new Date().toISOString() : parsed.toISOString()
}

function signedAmount(t: BankTransaction): number {
  const raw = t.transaction_amount.amount
  const isDebit = t.credit_debit_indicator === 'DBIT'
  const num = Number(raw)
  if (raw.startsWith('-') || raw.startsWith('+')) return num
  return isDebit ? -Math.abs(num) : Math.abs(num)
}

async function ensureAccountForUid(
  connectionId: string,
  uid: string,
  details: AccountDetails,
  aspspName: string,
): Promise<string> {
  const existing = await db
    .select()
    .from(accounts)
    .where(and(eq(accounts.syncProvider, 'enable_banking'), eq(accounts.syncExternalId, uid)))
    .get()

  if (existing) {
    if (existing.bankConnectionId !== connectionId) {
      await db
        .update(accounts)
        .set({ bankConnectionId: connectionId, updatedAt: new Date().toISOString() })
        .where(eq(accounts.id, existing.id))
    }
    return existing.id
  }

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
  config: EnableBankingConfig,
  florinAccountId: string,
  remoteUid: string,
  isFirstSync: boolean,
  rules: ReadonlyArray<Rule>,
  syncStartDate: string,
): Promise<number> {
  const lookbackDays = isFirstSync ? TX_LOOKBACK_DAYS_INITIAL : TX_LOOKBACK_DAYS
  const dateTo = new Date()
  const psd2Floor = new Date(Date.now() - lookbackDays * 24 * 60 * 60 * 1000)

  // Per-account watermark — pick up the day AFTER the latest existing
  // transaction on this account.
  const latestExisting = await db
    .select()
    .from(transactions)
    .where(and(eq(transactions.accountId, florinAccountId), isNull(transactions.deletedAt)))
    .orderBy(desc(transactions.occurredAt))
    .limit(1)
    .get()

  const syncStartMs = new Date(syncStartDate).getTime()
  const accountWatermark = latestExisting
    ? new Date(new Date(latestExisting.occurredAt).getTime() + 24 * 60 * 60 * 1000)
    : new Date(syncStartMs)

  const dateFrom = accountWatermark > psd2Floor ? accountWatermark : psd2Floor
  if (dateFrom > dateTo) return 0

  let inserted = 0
  let continuationKey: string | undefined

  do {
    const page = await getTransactions(config, remoteUid, {
      dateFrom: isoDate(dateFrom),
      dateTo: isoDate(dateTo),
      continuationKey,
    })

    const rows: NewTransaction[] = page.transactions
      .filter((t) => Boolean(t.transaction_id ?? t.entry_reference))
      .map((t): NewTransaction => {
        const payee = pickPayee(t)
        const normalizedP = normalizePayee(payee)
        const amount = signedAmount(t)
        const externalId = t.transaction_id ?? t.entry_reference ?? null
        const categoryId = matchRule(
          { payee: normalizedP, amount, accountId: florinAccountId },
          rules,
        )
        return {
          accountId: florinAccountId,
          occurredAt: pickOccurredAt(t),
          amount,
          currency: t.transaction_amount.currency,
          payee,
          normalizedPayee: normalizedP,
          memo: t.note ?? null,
          categoryId,
          source: 'enable_banking',
          externalId,
          isPending: t.status === 'PDNG',
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

async function syncAccountBalance(
  config: EnableBankingConfig,
  florinAccountId: string,
  remoteUid: string,
): Promise<void> {
  const { balances } = await getBalances(config, remoteUid)
  const preference = ['ITAV', 'XPCD', 'CLAV', 'ITBD', 'CLBD'] as const
  const closing =
    preference.map((t) => balances.find((b) => b.balance_type === t)).find(Boolean) ?? balances[0]
  if (!closing) return
  await db
    .update(accounts)
    .set({
      currentBalance: Number(closing.balance_amount.amount),
      lastSyncedAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    })
    .where(eq(accounts.id, florinAccountId))
}

async function loadActiveRules(): Promise<ReadonlyArray<Rule>> {
  const rows = await db
    .select()
    .from(categorizationRules)
    .where(eq(categorizationRules.isActive, true))
    .all()
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
  const ebConfig = await getEnableBankingConfig()
  if (!ebConfig) {
    throw new Error('Enable Banking is not configured — set app id and private key path in settings.')
  }

  const connection = await db
    .select()
    .from(bankConnections)
    .where(eq(bankConnections.id, connectionId))
    .get()
  if (!connection) {
    throw new Error(`Bank connection ${connectionId} not found`)
  }

  const session = await getSession(ebConfig, connection.sessionId)
  if (session.status !== 'AUTHORIZED') {
    await db
      .update(bankConnections)
      .set({
        status: session.status === 'EXPIRED' ? 'expired' : 'revoked',
        lastSyncError: `Session is ${session.status} — re-authentication required`,
        updatedAt: new Date().toISOString(),
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
      const details = await getAccountDetails(ebConfig, uid)
      const florinAccountId = await ensureAccountForUid(
        connectionId,
        uid,
        details,
        connection.aspspName,
      )

      const priorTx = await db
        .select()
        .from(transactions)
        .where(
          and(
            eq(transactions.accountId, florinAccountId),
            eq(transactions.source, 'enable_banking'),
            isNotNull(transactions.externalId),
            isNull(transactions.deletedAt),
          ),
        )
        .limit(1)
        .get()

      const isFirstSync = !priorTx
      await syncAccountBalance(ebConfig, florinAccountId, uid)
      const inserted = await syncAccountTransactions(
        ebConfig,
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
      lastSyncedAt: new Date().toISOString(),
      lastSyncError: errors.length > 0 ? errors.map((e) => e.message).join('; ') : null,
      updatedAt: new Date().toISOString(),
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
