import Database from 'better-sqlite3'
import { drizzle } from 'drizzle-orm/better-sqlite3'
import * as schema from './schema'

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

  return drizzle(sqlite, { schema })
}

export type SqliteDB = ReturnType<typeof createSqliteClient>
