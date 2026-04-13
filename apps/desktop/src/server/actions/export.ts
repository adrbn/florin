'use server'

import { db } from '@/db/client'
import { exportAllDataMutation } from '@florin/db-sqlite'

/**
 * Snapshot every Florin table into a single JSON payload. Used by the
 * Settings page "Export data" button.
 */
export async function exportAllData() {
  return await exportAllDataMutation(db)
}
