/**
 * Lazy background scheduler for bank syncs. Kicked off from the root layout
 * on the first request after the server boots, then keeps running for the
 * life of the Node process.
 *
 * Why this pattern instead of `instrumentation.ts`:
 *
 *   - `instrumentation.ts` is compiled for BOTH the Node and Edge runtimes
 *     and webpack eagerly analyses the full import graph even through
 *     dynamic imports, so pulling in `postgres` / `node:crypto` from there
 *     blows up the Edge bundle.
 *
 *   - This file, by contrast, is only ever imported from server-side code
 *     that already runs on the Node runtime (root layout, server actions),
 *     so Next.js never tries to compile it for Edge.
 *
 *   - The `schedulerStarted` module-level flag is a per-process singleton:
 *     the first call arms the interval, subsequent calls are no-ops. Inside
 *     a single long-lived Next.js container that's all we need. If you ever
 *     run Florin under PM2 cluster mode or k8s replicas > 1 you'll want to
 *     gate this behind a leader-election check to avoid duplicate syncs.
 *
 *   - First sync fires after a 2-minute warmup so we don't race a fresh
 *     `docker compose up` migration. Subsequent syncs fire every 6 hours,
 *     well within PSD2 quotas (Enable Banking allows 4 unattended pulls
 *     per 24h window for LBP).
 *
 *   - Errors are logged and swallowed so one bad run doesn't kill the loop.
 *     Per-connection error messages are already persisted onto
 *     `bank_connections.last_sync_error` by `syncConnection` itself, so the
 *     Accounts page surfaces them without extra plumbing.
 */

import { syncAllConnections } from './sync-all'

const SYNC_INTERVAL_MS = 6 * 60 * 60 * 1000 // 6 hours
const INITIAL_DELAY_MS = 2 * 60 * 1000 // 2 minutes

let schedulerStarted = false

export function ensureAutoSyncScheduler(): void {
  if (schedulerStarted) return
  if (process.env.NODE_ENV === 'test') return
  if (process.env.FLORIN_DISABLE_AUTO_SYNC === '1') return
  schedulerStarted = true

  const runOnce = async (tag: string): Promise<void> => {
    const startedAt = Date.now()
    try {
      const result = await syncAllConnections('scheduler')
      const durationSeconds = ((Date.now() - startedAt) / 1000).toFixed(1)
      console.log(
        `[florin:auto-sync:${tag}] ${result.connectionsSynced} connections, ${result.accountsSynced} accounts, +${result.transactionsInserted} transactions, ${durationSeconds}s` +
          (result.errors.length > 0 ? ` — errors: ${result.errors.length}` : ''),
      )
    } catch (error: unknown) {
      const message = error instanceof Error ? error.message : 'unknown error'
      console.error(`[florin:auto-sync:${tag}] failed: ${message}`)
    }
  }

  setTimeout(() => {
    void runOnce('initial')
    setInterval(() => {
      void runOnce('periodic')
    }, SYNC_INTERVAL_MS)
  }, INITIAL_DELAY_MS)

  console.log(
    `[florin:auto-sync] registered — initial run in ${INITIAL_DELAY_MS / 1000}s, then every ${SYNC_INTERVAL_MS / 1000 / 3600}h`,
  )
}
