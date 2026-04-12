import path from 'node:path'
import { createSqliteClient, createSqliteQueries, createSqliteMutations } from '@florin/db-sqlite'

// In Electron, app.getPath('userData') resolves to ~/Library/Application Support/Florin
// For the Next.js server side, we use a fixed path. In production this will be set by the Electron main process.
const DB_PATH = process.env.FLORIN_DB_PATH || path.join(process.cwd(), 'florin.db')

const db = createSqliteClient(DB_PATH)
export { db }
export const queries = createSqliteQueries(db)
export const mutations = createSqliteMutations(db)
export type DB = typeof db
