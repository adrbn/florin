import type { PgDB } from '../client'
import {
  accounts,
  bankConnections,
  categories,
  categorizationRules,
  categoryGroups,
  transactions,
} from '../schema'

export interface ExportPayload {
  exportedAt: string
  schemaVersion: 1
  accounts: unknown[]
  categoryGroups: unknown[]
  categories: unknown[]
  categorizationRules: unknown[]
  transactions: unknown[]
  bankConnections: unknown[]
}

/**
 * Snapshot every Florin table into a single JSON payload. Strips the bank
 * connection sessionId to avoid leaking a long-lived consent token.
 */
export async function exportAllDataMutation(db: PgDB): Promise<ExportPayload> {
  const [
    accountRows,
    categoryGroupRows,
    categoryRows,
    ruleRows,
    transactionRows,
    bankConnectionRows,
  ] = await Promise.all([
    db.select().from(accounts),
    db.select().from(categoryGroups),
    db.select().from(categories),
    db.select().from(categorizationRules),
    db.select().from(transactions),
    db.select().from(bankConnections),
  ])

  return {
    exportedAt: new Date().toISOString(),
    schemaVersion: 1,
    accounts: accountRows,
    categoryGroups: categoryGroupRows,
    categories: categoryRows,
    categorizationRules: ruleRows,
    transactions: transactionRows,
    bankConnections: bankConnectionRows.map((row) => {
      const { sessionId: _sessionId, ...safe } = row
      return safe
    }),
  }
}
