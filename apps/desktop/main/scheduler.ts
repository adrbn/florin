/**
 * Background sync scheduler for the Electron main process.
 *
 * Performs an initial bank sync after a 2-minute warmup (so the app doesn't
 * hammer the API on every restart during development), then re-syncs every 6
 * hours. PSD2 data doesn't change more than once or twice a day, so 6 hours
 * is a good tradeoff between freshness and rate-limit headroom.
 */

let intervalId: NodeJS.Timeout | null = null
let warmupId: NodeJS.Timeout | null = null

const WARMUP_MS = 2 * 60 * 1000 // 2 minutes
const INTERVAL_MS = 6 * 60 * 60 * 1000 // 6 hours

export interface SyncStatus {
  isSyncing: boolean
  lastSyncAt: Date | null
  lastError: string | null
}

const status: SyncStatus = {
  isSyncing: false,
  lastSyncAt: null,
  lastError: null,
}

export function getSyncStatus(): Readonly<SyncStatus> {
  return { ...status }
}

export function startSyncScheduler(syncFn: () => Promise<void>): void {
  const wrappedSync = async () => {
    if (status.isSyncing) return
    status.isSyncing = true
    status.lastError = null
    try {
      await syncFn()
      status.lastSyncAt = new Date()
    } catch (error: unknown) {
      status.lastError = error instanceof Error ? error.message : 'unknown error'
    } finally {
      status.isSyncing = false
    }
  }

  // Initial sync after warmup
  warmupId = setTimeout(() => {
    wrappedSync().catch(() => {})
  }, WARMUP_MS)

  // Then every 6 hours
  intervalId = setInterval(() => {
    wrappedSync().catch(() => {})
  }, INTERVAL_MS)
}

export function stopSyncScheduler(): void {
  if (warmupId) {
    clearTimeout(warmupId)
    warmupId = null
  }
  if (intervalId) {
    clearInterval(intervalId)
    intervalId = null
  }
}
