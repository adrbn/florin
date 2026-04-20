import Database from 'better-sqlite3'
import { drizzle } from 'drizzle-orm/better-sqlite3'
import * as schema from './schema'

// Module-level cache so ensureSchema can reach the underlying better-sqlite3
// handle without forcing every caller to hold onto it.
const rawByDrizzle = new WeakMap<object, Database.Database>()

/**
 * Create a Drizzle ORM client backed by better-sqlite3.
 *
 * Enables WAL mode and foreign keys for performance and integrity.
 */
export function createSqliteClient(dbPath: string) {
  const sqlite = new Database(dbPath)

  // Enable WAL mode for better concurrent read/write performance
  sqlite.pragma('journal_mode = WAL')
  // Enforce foreign key constraints (off by default in SQLite)
  sqlite.pragma('foreign_keys = ON')

  const db = drizzle(sqlite, { schema })
  rawByDrizzle.set(db as unknown as object, sqlite)
  return db
}

export function getRawSqlite(db: SqliteDB): Database.Database {
  const raw = rawByDrizzle.get(db as unknown as object)
  if (!raw) throw new Error('Drizzle client was not created via createSqliteClient')
  return raw
}

export type SqliteDB = ReturnType<typeof createSqliteClient>
