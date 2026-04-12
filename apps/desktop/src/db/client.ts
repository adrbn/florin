import path from 'node:path'
import { createSqliteClient, createSqliteQueries, createSqliteMutations } from '@florin/db-sqlite'

const DB_PATH = process.env.FLORIN_DB_PATH || path.join(process.cwd(), 'florin.db')

// Lazy singletons — avoids creating the DB at import time, preventing
// SQLITE_BUSY during Next.js build when multiple workers import this module.
let _db: ReturnType<typeof createSqliteClient>
let _queries: ReturnType<typeof createSqliteQueries>
let _mutations: ReturnType<typeof createSqliteMutations>

function ensureDb() {
  if (!_db) {
    _db = createSqliteClient(DB_PATH)
    _queries = createSqliteQueries(_db)
    _mutations = createSqliteMutations(_db)
  }
}

export const db = new Proxy({} as ReturnType<typeof createSqliteClient>, {
  get(_, prop) { ensureDb(); return Reflect.get(_db, prop) },
})
export const queries = new Proxy({} as ReturnType<typeof createSqliteQueries>, {
  get(_, prop) { ensureDb(); return Reflect.get(_queries, prop) },
})
export const mutations = new Proxy({} as ReturnType<typeof createSqliteMutations>, {
  get(_, prop) { ensureDb(); return Reflect.get(_mutations, prop) },
})
export type DB = ReturnType<typeof createSqliteClient>
