import { drizzle } from 'drizzle-orm/postgres-js'
import postgres from 'postgres'
import * as schema from './schema'

/**
 * Create a Drizzle ORM client backed by postgres-js.
 *
 * In dev mode, the underlying postgres-js pool is cached on globalThis so that
 * Next.js HMR doesn't open a new pool on every module reload and exhaust
 * Postgres max_connections. In production, the module evaluates once so the
 * guard is a no-op.
 */
export function createPgClient(databaseUrl: string) {
  const globalForPg = globalThis as unknown as {
    __florinPg?: ReturnType<typeof postgres>
  }

  const queryClient =
    globalForPg.__florinPg ??
    postgres(databaseUrl, {
      max: 5,
      idle_timeout: 20,
      max_lifetime: 60 * 30,
    })

  if (process.env.NODE_ENV !== 'production') {
    globalForPg.__florinPg = queryClient
  }

  return drizzle(queryClient, { schema })
}

export type PgDB = ReturnType<typeof createPgClient>
