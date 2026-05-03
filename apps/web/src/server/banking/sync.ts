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
  bankSyncAccountResults,
  bankSyncRuns,
  categorizationRules,
  type NewTransaction,
  transactions,
} from '@/db/schema'
import {
  matchRule,
  type Rule,
  normalizePayee,
  suggestCategory,
  type HistoryEntry,
} from '@florin/core/lib/categorization'
import { extractTrueDateFromText } from '@florin/core/lib/transactions'
import { autoLinkInternalTransfersMutation } from '@florin/db-pg'
import { getAccountDetails, getBalances, getSession, getTransactions } from './enable-banking'
import type { AccountDetails, BankTransaction } from './types'

export interface SyncResult {
  connectionId: string
  accountsSynced: number
  transactionsInserted: number
  errors: ReadonlyArray<{ accountUid: string; message: string }>
  durationMs: number
}

export type SyncTrigger = 'manual' | 'scheduler' | 'initial'

/** Per-account result accumulator used while a run is in progress. */
interface AccountLog {
  accountUid: string
  accountId: string | null
  balanceFetched: boolean
  balanceError: string | null
  detailsError: string | null
  txFetched: number
  txInserted: number
  txError: string | null
}

function newAccountLog(uid: string): AccountLog {
  return {
    accountUid: uid,
    accountId: null,
    balanceFetched: false,
    balanceError: null,
    detailsError: null,
    txFetched: 0,
    txInserted: 0,
    txError: null,
  }
}

function buildErrorSummary(
  errors: ReadonlyArray<{ accountUid: string; message: string }>,
): string | null {
  if (errors.length === 0) return null
  const joined = errors.map((e) => `${e.accountUid}: ${e.message}`).join('; ')
  return joined.length > 400 ? `${joined.slice(0, 397)}…` : joined
}

async function finalizeSyncRun(
  runId: string,
  startedAtMs: number,
  status: 'ok' | 'partial' | 'error',
  accountsTotal: number,
  accountsOk: number,
  totalInserted: number,
  errors: ReadonlyArray<{ accountUid: string; message: string }>,
  accountLogs: ReadonlyArray<AccountLog>,
) {
  await db
    .update(bankSyncRuns)
    .set({
      finishedAt: new Date(),
      status,
      accountsTotal,
      accountsOk,
      txInserted: totalInserted,
      errorSummary: buildErrorSummary(errors),
      durationMs: Date.now() - startedAtMs,
    })
    .where(eq(bankSyncRuns.id, runId))

  if (accountLogs.length > 0) {
    await db.insert(bankSyncAccountResults).values(
      accountLogs.map((a) => ({
        runId,
        accountUid: a.accountUid,
        accountId: a.accountId,
        balanceFetched: a.balanceFetched,
        balanceError: a.balanceError,
        detailsError: a.detailsError,
        txFetched: a.txFetched,
        txInserted: a.txInserted,
        txError: a.txError,
      })),
    )
  }
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

function pickOccurredAt(t: BankTransaction, payeeText: string): Date {
  // Prefer value_date (economic effect) over booking_date. Then, if the
  // payee line embeds a date (common with French bank card purchases like
  // "ACHAT CB 14.04.26"), use that when it's within ±14 days of the booked
  // date — it's the true transaction moment, not the next-business-day
  // posting.
  const raw = t.value_date ?? t.booking_date
  const booked = raw ? new Date(raw) : new Date()
  const bookedOk = !Number.isNaN(booked.getTime()) ? booked : new Date()
  const fromText = extractTrueDateFromText(payeeText, bookedOk)
  return fromText?.date ?? bookedOk
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
  history: ReadonlyArray<HistoryEntry>,
  syncStartDate: Date,
): Promise<{ fetched: number; inserted: number }> {
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
  if (dateFrom > dateTo) return { fetched: 0, inserted: 0 }
  let inserted = 0
  let fetched = 0
  let continuationKey: string | undefined

  do {
    const page = await getTransactions(remoteUid, {
      dateFrom: isoDate(dateFrom),
      dateTo: isoDate(dateTo),
      continuationKey,
    })
    fetched += page.transactions.length
    const rows: NewTransaction[] = page.transactions
      .filter((t) => Boolean(t.transaction_id ?? t.entry_reference))
      .map((t): NewTransaction => {
        const payee = pickPayee(t)
        const normalizedPayee = normalizePayee(payee)
        const amount = signedAmount(t)
        const externalId = t.transaction_id ?? t.entry_reference ?? null
        const numericAmount = Number(amount)
        let categoryId = matchRule(
          { payee: normalizedPayee, amount: numericAmount, accountId: florinAccountId },
          rules,
        )
        let needsReview = true
        if (categoryId !== null) {
          needsReview = false
        } else {
          const suggestion = suggestCategory(
            { normalizedPayee, amount: numericAmount, accountId: florinAccountId },
            history,
          )
          if (suggestion && suggestion.confidence >= 0.5) {
            categoryId = suggestion.categoryId
            needsReview = suggestion.confidence < 0.95
          }
        }
        return {
          accountId: florinAccountId,
          occurredAt: pickOccurredAt(t, payee),
          amount,
          currency: t.transaction_amount.currency,
          payee,
          normalizedPayee,
          memo: t.note ?? null,
          categoryId,
          source: 'enable_banking',
          externalId,
          isPending: t.status === 'PDNG',
          needsReview,
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

  return { fetched, inserted }
}

/** Pick the most accurate balance. Returns the chosen entry + type label. */
function pickBalance(
  balances: ReadonlyArray<{ balance_type?: string; balance_amount: { amount: string; currency: string } }>,
): { amount: number; type: string; allTypes: string } | null {
  if (balances.length === 0) return null

  const allTypes = balances.map((b) => `${b.balance_type ?? '?'}=${b.balance_amount.amount}`).join(', ')

  // Prefer booked (actual funds), then available (includes overdraft) as fallback.
  const preference = ['CLBD', 'ITBD', 'XPCD', 'CLAV', 'ITAV'] as const
  const chosen =
    preference.map((t) => balances.find((b) => b.balance_type === t)).find(Boolean) ?? balances[0]
  if (!chosen) return null

  return {
    amount: Number(chosen.balance_amount.amount),
    type: chosen.balance_type ?? 'unknown',
    allTypes,
  }
}

async function syncAccountBalance(florinAccountId: string, remoteUid: string): Promise<string> {
  const { balances } = await getBalances(remoteUid)
  const picked = pickBalance(balances)
  if (!picked) {
    await db
      .update(accounts)
      .set({ lastSyncedAt: new Date(), updatedAt: new Date() })
      .where(eq(accounts.id, florinAccountId))
    return 'no balances returned'
  }

  await db
    .update(accounts)
    .set({
      currentBalance: String(picked.amount),
      lastSyncedAt: new Date(),
      updatedAt: new Date(),
    })
    .where(eq(accounts.id, florinAccountId))

  return `balance=${picked.amount} (${picked.type}) [${picked.allTypes}]`
}

/**
 * Fetch a pool of the most recent categorised transactions to feed the
 * history-similarity matcher. Excludes transfers and soft-deleted rows.
 */
async function loadCategorizedHistory(): Promise<ReadonlyArray<HistoryEntry>> {
  const rows = await db
    .select({
      normalizedPayee: transactions.normalizedPayee,
      categoryId: transactions.categoryId,
      amount: transactions.amount,
      accountId: transactions.accountId,
    })
    .from(transactions)
    .where(
      and(
        isNotNull(transactions.categoryId),
        isNull(transactions.deletedAt),
        isNull(transactions.transferPairId),
      ),
    )
    .orderBy(desc(transactions.occurredAt))
    .limit(5000)
  return rows
    .filter(
      (r): r is typeof r & { categoryId: string; accountId: string } =>
        r.categoryId !== null && r.accountId !== null && r.normalizedPayee.length > 0,
    )
    .map((r) => ({
      normalizedPayee: r.normalizedPayee,
      categoryId: r.categoryId,
      amount: Number(r.amount),
      accountId: r.accountId,
    }))
}

/**
 * Re-run categorisation on every transaction still flagged needs_review using
 * the freshly enriched history pool, then auto-clear high-confidence matches.
 */
async function reEvaluateReviewQueue(
  rules: ReadonlyArray<Rule>,
  history: ReadonlyArray<HistoryEntry>,
): Promise<{ autoApplied: number; suggested: number }> {
  const pending = await db
    .select({
      id: transactions.id,
      accountId: transactions.accountId,
      amount: transactions.amount,
      normalizedPayee: transactions.normalizedPayee,
      categoryId: transactions.categoryId,
    })
    .from(transactions)
    .where(and(eq(transactions.needsReview, true), isNull(transactions.deletedAt)))

  let autoApplied = 0
  let suggested = 0
  const now = new Date()

  for (const tx of pending) {
    if (!tx.normalizedPayee || !tx.accountId) continue
    const amount = Number(tx.amount)
    const payee = tx.normalizedPayee
    const accountId = tx.accountId

    const ruleHit = matchRule({ payee, amount, accountId }, rules)
    if (ruleHit !== null) {
      await db
        .update(transactions)
        .set({ categoryId: ruleHit, needsReview: false, updatedAt: now })
        .where(eq(transactions.id, tx.id))
      autoApplied += 1
      continue
    }

    const suggestion = suggestCategory(
      { normalizedPayee: payee, amount, accountId },
      history,
    )
    if (!suggestion) continue
    if (suggestion.confidence >= 0.95) {
      await db
        .update(transactions)
        .set({ categoryId: suggestion.categoryId, needsReview: false, updatedAt: now })
        .where(eq(transactions.id, tx.id))
      autoApplied += 1
    } else if (suggestion.confidence >= 0.5 && tx.categoryId === null) {
      await db
        .update(transactions)
        .set({ categoryId: suggestion.categoryId, updatedAt: now })
        .where(eq(transactions.id, tx.id))
      suggested += 1
    }
  }

  return { autoApplied, suggested }
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
 *
 * Every invocation writes one bank_sync_runs row plus one
 * bank_sync_account_results row per remote account UID, so the /settings
 * sync-log UI can show users exactly what happened.
 */
export async function syncConnection(
  connectionId: string,
  trigger: SyncTrigger = 'manual',
): Promise<SyncResult> {
  const startedAt = Date.now()
  const connection = await db.query.bankConnections.findFirst({
    where: eq(bankConnections.id, connectionId),
  })
  if (!connection) {
    throw new Error(`Bank connection ${connectionId} not found`)
  }

  const [runRow] = await db
    .insert(bankSyncRuns)
    .values({
      connectionId,
      trigger,
      status: 'running',
    })
    .returning({ id: bankSyncRuns.id })
  const runId = runRow?.id
  if (!runId) {
    throw new Error('Failed to create sync run row')
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
    const errors = [{ accountUid: '*', message: `Session ${session.status}` }]
    await finalizeSyncRun(runId, startedAt, 'error', 0, 0, 0, errors, [])
    return {
      connectionId,
      accountsSynced: 0,
      transactionsInserted: 0,
      errors,
      durationMs: Date.now() - startedAt,
    }
  }

  const [rules, history] = await Promise.all([loadActiveRules(), loadCategorizedHistory()])
  const errors: { accountUid: string; message: string }[] = []
  const accountLogs: AccountLog[] = []
  let totalInserted = 0
  let accountsSynced = 0

  for (const uid of session.accounts) {
    const log = newAccountLog(uid)
    accountLogs.push(log)

    // Fetch account details — if this fails the UID is unusable, skip it.
    let details: AccountDetails
    try {
      details = await getAccountDetails(uid)
    } catch (error: unknown) {
      const message = error instanceof Error ? error.message : 'unknown error'
      const msg = `details: ${message}`
      errors.push({ accountUid: uid, message: msg })
      log.detailsError = msg
      continue
    }

    const florinAccountId = await ensureAccountForUid(
      connectionId,
      uid,
      details,
      connection.aspspName,
    )
    log.accountId = florinAccountId

    // Balance and transactions sync independently — a 422 on transactions
    // must not prevent the balance from updating.
    try {
      await syncAccountBalance(florinAccountId, uid)
      log.balanceFetched = true
    } catch (error: unknown) {
      const message = error instanceof Error ? error.message : 'unknown error'
      const msg = `balance: ${message}`
      errors.push({ accountUid: uid, message: msg })
      log.balanceError = msg
    }

    try {
      const priorTx = await db.query.transactions.findFirst({
        where: and(
          eq(transactions.accountId, florinAccountId),
          eq(transactions.source, 'enable_banking'),
          isNotNull(transactions.externalId),
          isNull(transactions.deletedAt),
        ),
      })
      const isFirstSync = !priorTx
      const { fetched, inserted } = await syncAccountTransactions(
        florinAccountId,
        uid,
        isFirstSync,
        rules,
        history,
        connection.syncStartDate,
      )
      totalInserted += inserted
      log.txFetched = fetched
      log.txInserted = inserted
    } catch (error: unknown) {
      const message = error instanceof Error ? error.message : 'unknown error'
      const msg = `transactions: ${message}`
      errors.push({ accountUid: uid, message: msg })
      log.txError = msg
    }

    if (log.balanceFetched) {
      accountsSynced += 1
    }
  }

  if (totalInserted > 0) {
    try {
      const freshHistory = await loadCategorizedHistory()
      await reEvaluateReviewQueue(rules, freshHistory)
    } catch {
      // Never fail a sync because of review-queue rescoring.
    }

    try {
      await autoLinkInternalTransfersMutation(db)
    } catch {
      // Auto-pairing is a UX nicety, not a correctness invariant — never
      // fail a sync because of it.
    }
  }

  await db
    .update(bankConnections)
    .set({
      // Reaching this point means getSession returned AUTHORIZED — flip the
      // status back to 'active' so a transient failure that previously
      // marked the connection 'expired' / 'revoked' doesn't make it
      // permanently invisible to syncAllConnections (which filters on
      // status='active').
      status: 'active',
      lastSyncedAt: new Date(),
      lastSyncError: errors.length > 0 ? errors.map((e) => e.message).join('; ') : null,
      updatedAt: new Date(),
    })
    .where(eq(bankConnections.id, connectionId))

  const accountsTotal = session.accounts.length
  const status: 'ok' | 'partial' | 'error' =
    errors.length === 0 ? 'ok' : accountsSynced === 0 ? 'error' : 'partial'
  await finalizeSyncRun(
    runId,
    startedAt,
    status,
    accountsTotal,
    accountsSynced,
    totalInserted,
    errors,
    accountLogs,
  )

  return {
    connectionId,
    accountsSynced,
    transactionsInserted: totalInserted,
    errors,
    durationMs: Date.now() - startedAt,
  }
}
