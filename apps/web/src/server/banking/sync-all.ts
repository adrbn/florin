/**
 * Fan-out sync across every active bank connection. Used by both the
 * dashboard "Sync now" button and the background scheduler registered in
 * `src/instrumentation.ts`.
 *
 * Runs connections sequentially on purpose — Enable Banking rate-limits per
 * client_id, and a self-hosted user is unlikely to have more than one or two
 * linked banks, so the serialization cost is negligible.
 */
import { eq } from 'drizzle-orm'
import { db } from '@/db/client'
import { bankConnections } from '@/db/schema'
import { type SyncResult, syncConnection } from './sync'

export interface SyncAllResult {
  connectionsSynced: number
  accountsSynced: number
  transactionsInserted: number
  errors: ReadonlyArray<{ connectionId: string; message: string }>
  durationMs: number
}

export async function syncAllConnections(): Promise<SyncAllResult> {
  const startedAt = Date.now()
  const active = await db
    .select({ id: bankConnections.id, aspspName: bankConnections.aspspName })
    .from(bankConnections)
    .where(eq(bankConnections.status, 'active'))

  const errors: { connectionId: string; message: string }[] = []
  let accountsSynced = 0
  let transactionsInserted = 0

  for (const conn of active) {
    try {
      const result: SyncResult = await syncConnection(conn.id)
      accountsSynced += result.accountsSynced
      transactionsInserted += result.transactionsInserted
      if (result.errors.length > 0) {
        errors.push({
          connectionId: conn.id,
          message: result.errors.map((e) => e.message).join('; '),
        })
      }
    } catch (error: unknown) {
      const message = error instanceof Error ? error.message : 'unknown error'
      errors.push({ connectionId: conn.id, message })
    }
  }

  return {
    connectionsSynced: active.length,
    accountsSynced,
    transactionsInserted,
    errors,
    durationMs: Date.now() - startedAt,
  }
}
