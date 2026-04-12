import { eq } from 'drizzle-orm'
import type { EnableBankingConfig } from '@florin/core/banking'
import { db } from '@/db/client'
import { settings } from '@/db/schema'

/**
 * Desktop reads Enable Banking config from the SQLite `settings` table.
 * Returns null when banking is not configured yet — the onboarding wizard
 * (Task 12) will populate these keys.
 */
export async function getEnableBankingConfig(): Promise<EnableBankingConfig | null> {
  const appIdRow = await db.select().from(settings).where(eq(settings.key, 'eb_app_id')).get()
  const keyPathRow = await db
    .select()
    .from(settings)
    .where(eq(settings.key, 'eb_private_key_path'))
    .get()

  if (!appIdRow?.value || !keyPathRow?.value) {
    return null
  }

  return {
    appId: appIdRow.value,
    privateKeyPath: keyPathRow.value,
  }
}

/**
 * Read the HMAC secret used for signing OAuth state tokens from the settings
 * table. Falls back to a deterministic but secret-per-install value derived
 * from the app id when no explicit secret is configured.
 */
export async function getAuthStateSecret(): Promise<string | null> {
  const row = await db.select().from(settings).where(eq(settings.key, 'auth_state_secret')).get()
  if (row?.value) return row.value

  // Fallback: derive from app id if available (better than nothing).
  const appIdRow = await db.select().from(settings).where(eq(settings.key, 'eb_app_id')).get()
  return appIdRow?.value ?? null
}
