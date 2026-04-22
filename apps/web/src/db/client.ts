import {
  createPgClient,
  createPgMutations,
  createPgQueries,
  ensurePgRuntimePatches,
} from '@florin/db-pg'
import { env } from '@/server/env'

export const db = createPgClient(env.DATABASE_URL)
export const queries = createPgQueries(db)
export const mutations = createPgMutations(db)
export type DB = typeof db

// Fire-and-forget idempotent schema patch. Runs once at server boot; if the
// pool was cached on globalThis (HMR), the guard below makes sure we only
// attempt it once per process so dev reloads don't spam the DB.
const globalForBootstrap = globalThis as unknown as { __florinPgPatched?: boolean }
if (!globalForBootstrap.__florinPgPatched) {
  globalForBootstrap.__florinPgPatched = true
  ensurePgRuntimePatches(db).catch((err) => {
    console.error('ensurePgRuntimePatches failed', err)
  })
}
