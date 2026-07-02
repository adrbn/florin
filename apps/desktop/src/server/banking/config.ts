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
 * table, generating a cryptographically random one on first use. The old
 * fallback (deriving from the Enable Banking app id) was weak: the app id is
 * a non-secret UUID visible in the EB console and API traffic, so anyone who
 * knew it could forge state tokens.
 */
export async function getAuthStateSecret(): Promise<string | null> {
  const row = await db.select().from(settings).where(eq(settings.key, 'auth_state_secret')).get()
  if (row?.value) return row.value

  const { randomBytes } = await import('node:crypto')
  const secret = randomBytes(32).toString('hex')
  await db
    .insert(settings)
    .values({ key: 'auth_state_secret', value: secret })
    .onConflictDoNothing()
  // Re-read: a concurrent caller may have won the insert race — both callers
  // must agree on the same secret or the auth state check fails spuriously.
  const persisted = await db
    .select()
    .from(settings)
    .where(eq(settings.key, 'auth_state_secret'))
    .get()
  return persisted?.value ?? secret
}
