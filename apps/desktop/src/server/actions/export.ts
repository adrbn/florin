'use server'

import { db } from '@/db/client'
import { exportAllDataMutation } from '@florin/db-sqlite'

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
 * Settings page "Export data" button.
 */
export async function exportAllData(): Promise<ExportPayload> {
  return exportAllDataMutation(db)
}
