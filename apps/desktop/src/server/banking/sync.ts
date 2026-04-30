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
  EnableBankingError,
  getAccountDetails,
  getBalances,
  getSession,
  getTransactions,
} from '@florin/core/banking'
import type { AccountDetails, BankTransaction } from '@florin/core/banking'
import {
  matchRule,
  type Rule,
  normalizePayee,
  suggestCategory,
  type HistoryEntry,
} from '@florin/core/lib/categorization'
import { extractTrueDateFromText } from '@florin/core/lib/transactions'
import { autoLinkInternalTransfersMutation } from '@florin/db-sqlite'
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
import { getEnableBankingConfig } from './config'

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

/** Build a short error string tagged with which operation failed. */
function shortError(op: string, error: unknown): string {
  if (error instanceof EnableBankingError) {
    return `${op}: API ${error.status ?? '?'} — ${extractShortReason(error)}`
  }
  return `${op}: ${error instanceof Error ? error.message : 'unknown error'}`
}

/** Pull a short human-readable reason from a verbose EnableBankingError. */
function extractShortReason(error: EnableBankingError): string {
  const body = error.body as Record<string, unknown> | undefined
  if (body && typeof body === 'object') {
    // Enable Banking errors often have a `message` or `error` field
    if (typeof body.message === 'string') return body.message
    if (typeof body.error === 'string') return body.error
  }
  // Fallback: strip the verbose prefix "Enable Banking API 422 on GET /path — ..."
  const msg = error.message
  const dashIdx = msg.indexOf(' — ')
  if (dashIdx > 0) {
    const after = msg.slice(dashIdx + 3, dashIdx + 103)
    return after.length < msg.slice(dashIdx + 3).length ? `${after}…` : after
  }
  return msg.slice(0, 100)
}

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

function pickOccurredAt(t: BankTransaction, payeeText: string): string {
  const raw = t.value_date ?? t.booking_date
  const booked = raw ? new Date(raw) : new Date()
  const bookedOk = !Number.isNaN(booked.getTime()) ? booked : new Date()
  // Prefer the date embedded in the free-text payee line when it's within
  // ±14 days of the booked date — banks book card purchases on the next
  // business day, so the booked date drifts across months/weekends.
  const fromText = extractTrueDateFromText(payeeText, bookedOk)
  return (fromText?.date ?? bookedOk).toISOString()
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
  history: ReadonlyArray<HistoryEntry>,
  syncStartDate: string,
): Promise<{ fetched: number; inserted: number }> {
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
  if (dateFrom > dateTo) return { fetched: 0, inserted: 0 }

  let inserted = 0
  let fetched = 0
  let continuationKey: string | undefined

  do {
    const page = await getTransactions(config, remoteUid, {
      dateFrom: isoDate(dateFrom),
      dateTo: isoDate(dateTo),
      continuationKey,
    })

    fetched += page.transactions.length

    const rows: NewTransaction[] = page.transactions
      .filter((t) => Boolean(t.transaction_id ?? t.entry_reference))
      .map((t): NewTransaction => {
        const payee = pickPayee(t)
        const normalizedP = normalizePayee(payee)
        const amount = signedAmount(t)
        const externalId = t.transaction_id ?? t.entry_reference ?? null
        // Two-step auto-categorisation. Explicit rules win; if no rule matches,
        // fall back to a history-similarity suggestion. Strong matches (≥0.95,
        // typically multiple past tx with the exact same payee all going to
        // the same category) are auto-applied and cleared from the review
        // queue — everything else gets pre-filled but left for human review.
        let categoryId = matchRule(
          { payee: normalizedP, amount, accountId: florinAccountId },
          rules,
        )
        let needsReview = true
        if (categoryId !== null) {
          // Rule match is explicit user intent — no need to flag for review.
          needsReview = false
        } else {
          const suggestion = suggestCategory(
            { normalizedPayee: normalizedP, amount, accountId: florinAccountId },
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
          normalizedPayee: normalizedP,
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

async function syncAccountBalance(
  config: EnableBankingConfig,
  florinAccountId: string,
  remoteUid: string,
): Promise<string> {
  const { balances } = await getBalances(config, remoteUid)
  const picked = pickBalance(balances)
  if (!picked) {
    await db
      .update(accounts)
      .set({ lastSyncedAt: new Date().toISOString(), updatedAt: new Date().toISOString() })
      .where(eq(accounts.id, florinAccountId))
    return 'no balances returned'
  }

  await db
    .update(accounts)
    .set({
      currentBalance: picked.amount,
      lastSyncedAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    })
    .where(eq(accounts.id, florinAccountId))

  return `balance=${picked.amount} (${picked.type}) [${picked.allTypes}]`
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
 * Fetch a pool of the most recent categorised transactions, to feed the
 * history-similarity matcher. Excludes transfers (they carry synthetic
 * payees that match nothing useful) and soft-deleted rows. Capped at 5000
 * rows — plenty for any realistic household yet cheap to iterate per-tx.
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
    .all()
  return rows.filter((r): r is HistoryEntry & { categoryId: string } =>
    r.categoryId !== null && r.normalizedPayee.length > 0,
  ).map((r) => ({
    normalizedPayee: r.normalizedPayee,
    categoryId: r.categoryId,
    amount: Number(r.amount),
    accountId: r.accountId,
  }))
}

/**
 * Re-run categorisation on every transaction still flagged `needs_review`.
 *
 * Why: the first pass in `syncAccountTransactions` ran with the history pool
 * as it was at the start of this sync. After we've ingested fresh rows, the
 * history is richer — a previously ambiguous tx might now have two siblings
 * with the same payee and a clear modal category, pushing confidence past
 * the auto-apply threshold. This pass catches those.
 *
 * Also re-checks rules, so newly created rules retroactively clean up the
 * review queue without the user having to click "apply to existing".
 *
 * Safe update policy:
 *   - Only touches `needs_review = true` rows (user-confirmed txs are off-limits).
 *   - Rule match → apply category, clear review flag (explicit user intent).
 *   - Similarity ≥ 0.95 → apply category, clear review flag.
 *   - Similarity 0.5–0.94 AND category still null → pre-fill category, keep flag.
 *   - Otherwise untouched.
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
    .all()

  let autoApplied = 0
  let suggested = 0
  const nowIso = new Date().toISOString()

  for (const tx of pending) {
    if (!tx.normalizedPayee || !tx.accountId) continue
    const amount = Number(tx.amount)
    const payee = tx.normalizedPayee
    const accountId = tx.accountId

    const ruleHit = matchRule(
      { payee, amount, accountId },
      rules,
    )
    if (ruleHit !== null) {
      await db
        .update(transactions)
        .set({ categoryId: ruleHit, needsReview: false, updatedAt: nowIso })
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
        .set({ categoryId: suggestion.categoryId, needsReview: false, updatedAt: nowIso })
        .where(eq(transactions.id, tx.id))
      autoApplied += 1
    } else if (suggestion.confidence >= 0.5 && tx.categoryId === null) {
      await db
        .update(transactions)
        .set({ categoryId: suggestion.categoryId, updatedAt: nowIso })
        .where(eq(transactions.id, tx.id))
      suggested += 1
    }
  }

  return { autoApplied, suggested }
}

/**
 * Truncate an error summary so it fits cleanly in the UI without dominating
 * the list view. Full per-account errors still live in bank_sync_account_results.
 */
function buildErrorSummary(
  errors: ReadonlyArray<{ accountUid: string; message: string }>,
): string | null {
  if (errors.length === 0) return null
  const joined = errors.map((e) => `${e.accountUid}: ${e.message}`).join('; ')
  return joined.length > 400 ? `${joined.slice(0, 397)}…` : joined
}

/** Finalize a sync_runs row with counts + status, then write account_results. */
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
      finishedAt: new Date().toISOString(),
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
 * Sync one bank connection end-to-end. Idempotent — safe to call repeatedly.
 * Returns counts and per-account errors instead of throwing on partial failure.
 *
 * Every invocation writes one bank_sync_runs row (status=running → ok/partial/error)
 * plus one bank_sync_account_results row per remote account UID, so the
 * /settings sync-log UI can show users exactly why their data looks the way
 * it does.
 */
export async function syncConnection(
  connectionId: string,
  trigger: SyncTrigger = 'manual',
): Promise<SyncResult> {
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

  // Open a run row up-front so concurrent callers (tray "Sync now" during a
  // scheduled sync) can see that something is in flight.
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

  let session: Awaited<ReturnType<typeof getSession>>
  try {
    session = await getSession(ebConfig, connection.sessionId)
  } catch (error: unknown) {
    // 422 / 404 on the session endpoint means the consent is dead — mark
    // the connection so the user knows to re-authenticate.
    const reason =
      error instanceof EnableBankingError
        ? `Session rejected (${error.status ?? '?'}) — reconnect this bank`
        : 'Failed to reach Enable Banking'
    await db
      .update(bankConnections)
      .set({ status: 'expired', lastSyncError: reason, updatedAt: new Date().toISOString() })
      .where(eq(bankConnections.id, connectionId))
    const errors = [{ accountUid: '*', message: reason }]
    await finalizeSyncRun(runId, startedAt, 'error', 0, 0, 0, errors, [])
    return {
      connectionId,
      accountsSynced: 0,
      transactionsInserted: 0,
      errors,
      durationMs: Date.now() - startedAt,
    }
  }

  if (session.status !== 'AUTHORIZED') {
    await db
      .update(bankConnections)
      .set({
        status: session.status === 'EXPIRED' ? 'expired' : 'revoked',
        lastSyncError: `Session is ${session.status} — re-authentication required`,
        updatedAt: new Date().toISOString(),
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
      details = await getAccountDetails(ebConfig, uid)
    } catch (error: unknown) {
      const msg = shortError('details', error)
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
    // (common for certain account types) must not prevent the balance from
    // updating. Each operation records its own error.
    try {
      await syncAccountBalance(ebConfig, florinAccountId, uid)
      log.balanceFetched = true
    } catch (error: unknown) {
      const msg = shortError('balance', error)
      errors.push({ accountUid: uid, message: msg })
      log.balanceError = msg
    }

    try {
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
      const { fetched, inserted } = await syncAccountTransactions(
        ebConfig,
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
      const msg = shortError('transactions', error)
      errors.push({ accountUid: uid, message: msg })
      log.txError = msg
    }

    // Count as synced if at least the balance updated
    if (log.balanceFetched) {
      accountsSynced += 1
    }
  }

  // Reload history (now enriched with the rows we just inserted) and re-score
  // the review queue. Cheap: matcher is O(n*history) over a few hundred rows
  // at most, and it's the moment when the user's history has the most signal
  // it's ever had.
  if (totalInserted > 0) {
    try {
      const freshHistory = await loadCategorizedHistory()
      await reEvaluateReviewQueue(rules, freshHistory)
    } catch {
      // Never fail a sync because of review-queue rescoring. Worst case the
      // user clears items manually on the next pass.
    }

    // Pair newly-inserted internal-transfer legs (e.g. CCP→Livret moves seen
    // as two opposite-signed rows on different accounts) so the Reflect
    // heatmap and category-breakdown queries — which all filter on
    // `transferPairId IS NULL` — stop double-counting them as expense+income.
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
      lastSyncedAt: new Date().toISOString(),
      lastSyncError: errors.length > 0 ? errors.map((e) => e.message).join('; ') : null,
      updatedAt: new Date().toISOString(),
    })
    .where(eq(bankConnections.id, connectionId))

  const accountsTotal = session.accounts.length
  const status: 'ok' | 'partial' | 'error' =
    errors.length === 0
      ? 'ok'
      : accountsSynced === 0
        ? 'error'
        : 'partial'
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
