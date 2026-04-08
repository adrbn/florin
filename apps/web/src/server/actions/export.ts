'use server'

import { db } from '@/db/client'
import {
  accounts,
  bankConnections,
  categories,
  categorizationRules,
  categoryGroups,
  transactions,
} from '@/db/schema'

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
 * Snapshot every Florin table into a single JSON payload. Used by the
 * Settings page "Export data" button. Stripping the bank connection
 * `sessionId` is intentional — that's a long-lived consent token and we
 * don't want it leaking into a JSON dump that might end up on a USB stick.
 */
export async function exportAllData(): Promise<ExportPayload> {
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
