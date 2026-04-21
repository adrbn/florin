/**
 * Read-side helper for the Sync log UI (web / PostgreSQL variant). Mirrors
 * apps/desktop/src/server/banking/sync-log.ts — same output shape, but
 * timestamps come back as Date objects from drizzle-pg so we serialize to
 * ISO strings for the client component.
 */
import { desc, eq, inArray } from 'drizzle-orm'
import type { SyncLogRunRow } from '@florin/core/components/settings/sync-log-card'
import { db } from '@/db/client'
import { accounts, bankConnections, bankSyncAccountResults, bankSyncRuns } from '@/db/schema'

const DEFAULT_LIMIT = 20

export async function listSyncLogRuns(limit = DEFAULT_LIMIT): Promise<SyncLogRunRow[]> {
  const runs = await db
    .select({
      id: bankSyncRuns.id,
      connectionId: bankSyncRuns.connectionId,
      trigger: bankSyncRuns.trigger,
      startedAt: bankSyncRuns.startedAt,
      finishedAt: bankSyncRuns.finishedAt,
      status: bankSyncRuns.status,
      accountsTotal: bankSyncRuns.accountsTotal,
      accountsOk: bankSyncRuns.accountsOk,
      txInserted: bankSyncRuns.txInserted,
      errorSummary: bankSyncRuns.errorSummary,
      durationMs: bankSyncRuns.durationMs,
      aspspName: bankConnections.aspspName,
    })
    .from(bankSyncRuns)
    .leftJoin(bankConnections, eq(bankSyncRuns.connectionId, bankConnections.id))
    .orderBy(desc(bankSyncRuns.startedAt))
    .limit(limit)

  if (runs.length === 0) return []

  const runIds = runs.map((r) => r.id)
  const results = await db
    .select({
      id: bankSyncAccountResults.id,
      runId: bankSyncAccountResults.runId,
      accountUid: bankSyncAccountResults.accountUid,
      accountId: bankSyncAccountResults.accountId,
      balanceFetched: bankSyncAccountResults.balanceFetched,
      balanceError: bankSyncAccountResults.balanceError,
      detailsError: bankSyncAccountResults.detailsError,
      txFetched: bankSyncAccountResults.txFetched,
      txInserted: bankSyncAccountResults.txInserted,
      txError: bankSyncAccountResults.txError,
      accountName: accounts.name,
    })
    .from(bankSyncAccountResults)
    .leftJoin(accounts, eq(bankSyncAccountResults.accountId, accounts.id))
    .where(inArray(bankSyncAccountResults.runId, runIds))

  const byRun = new Map<string, typeof results>()
  for (const row of results) {
    const bucket = byRun.get(row.runId) ?? []
    bucket.push(row)
    byRun.set(row.runId, bucket)
  }

  return runs.map((r) => ({
    id: r.id,
    connectionLabel: r.aspspName ?? 'Unknown bank',
    trigger: r.trigger,
    startedAt: r.startedAt.toISOString(),
    finishedAt: r.finishedAt ? r.finishedAt.toISOString() : null,
    status: r.status,
    accountsTotal: r.accountsTotal,
    accountsOk: r.accountsOk,
    txInserted: r.txInserted,
    errorSummary: r.errorSummary,
    durationMs: r.durationMs,
    accounts: (byRun.get(r.id) ?? []).map((a) => ({
      accountUid: a.accountUid,
      accountName: a.accountName,
      balanceFetched: a.balanceFetched,
      balanceError: a.balanceError,
      detailsError: a.detailsError,
      txFetched: a.txFetched,
      txInserted: a.txInserted,
      txError: a.txError,
    })),
  }))
}
