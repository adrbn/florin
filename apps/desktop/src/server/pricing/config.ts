import { eq } from 'drizzle-orm'
import type { PricingConfig } from '@florin/core/pricing'
import { db } from '@/db/client'
import { settings } from '@/db/schema'

/**
 * Desktop reads pricing config from the SQLite `settings` table. Keys:
 *   - `price_provider`  → 'yahoo' | 'none' (anything else collapses to 'none')
 *   - `price_api_key`   → optional, reserved for keyed providers
 *
 * Disabled by default (`none`) so the refresh job is a no-op until the user
 * opts in from the desktop Settings UI. Mirrors getEnableBankingConfig.
 */
export async function getPricingConfig(): Promise<PricingConfig> {
  const providerRow = await db
    .select()
    .from(settings)
    .where(eq(settings.key, 'price_provider'))
    .get()
  const keyRow = await db
    .select()
    .from(settings)
    .where(eq(settings.key, 'price_api_key'))
    .get()

  const provider = providerRow?.value === 'yahoo' ? 'yahoo' : 'none'
  return { provider, apiKey: keyRow?.value || undefined }
}
