import { drizzle } from 'drizzle-orm/postgres-js'
import postgres from 'postgres'
import { env } from '@/server/env'
import * as schema from './schema'

/**
 * In Next.js dev mode every file edit triggers HMR, which re-evaluates this
 * module. Without a guard each reload creates a fresh postgres-js pool of size
 * `max`, and the previous pools never get closed — within a few minutes we hit
 * Postgres `max_connections` (default 100) and queries fail with "too many
 * clients already". Cache the client on globalThis so HMR reuses one pool.
 *
 * In production this is a no-op (the module evaluates exactly once).
 */
const globalForPg = globalThis as unknown as {
  __florinPg?: ReturnType<typeof postgres>
}

const queryClient =
  globalForPg.__florinPg ??
  postgres(env.DATABASE_URL, {
    max: 5,
    idle_timeout: 20,
    max_lifetime: 60 * 30,
  })

if (process.env.NODE_ENV !== 'production') {
  globalForPg.__florinPg = queryClient
}

export const db = drizzle(queryClient, { schema })
export type DB = typeof db
