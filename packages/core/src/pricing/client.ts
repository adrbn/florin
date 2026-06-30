import type { PriceQuote, PricingConfig } from './types'
import { fetchYahooQuote } from './yahoo'

/**
 * Provider-dispatching price fetch. Returns `null` when the provider is
 * `'none'` (no network call at all), otherwise delegates to the matching
 * provider client. This is the seam where a keyed free-tier provider
 * (Tiingo/Polygon) plugs in later. Like the providers it never throws.
 */
export async function fetchQuote(
  config: PricingConfig,
  symbol: string,
): Promise<PriceQuote | null> {
  if (config.provider === 'none') return null
  if (config.provider === 'yahoo') return fetchYahooQuote(symbol)
  return null
}
