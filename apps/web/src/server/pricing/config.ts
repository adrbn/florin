import type { PricingConfig } from '@florin/core/pricing'
import { env } from '@/server/env'

/**
 * Web reads pricing config from environment variables. Disabled by default
 * (`PRICE_PROVIDER=none`) so the refresh job is a no-op until a self-hoster
 * opts in. Mirrors the Enable Banking env-config pattern.
 */
export function getPricingConfig(): PricingConfig {
  return {
    provider: env.PRICE_PROVIDER,
    apiKey: env.PRICE_API_KEY,
  }
}
