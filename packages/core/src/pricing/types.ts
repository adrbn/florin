/**
 * Pricing subsystem types. The client is DB-agnostic — config is passed in,
 * mirroring the Enable Banking client structure. See spec §3.3.
 */

/** Which price provider to use. `'none'` disables fetching (opt-in by default). */
export type PricingProvider = 'yahoo' | 'none'

export interface PricingConfig {
  provider: PricingProvider
  /** Optional, for keyed providers added later. Unused by 'yahoo'. */
  apiKey?: string
}

export interface PriceQuote {
  symbol: string
  price: number
  currency: string
  /** ISO timestamp of when the quote was fetched. */
  fetchedAt: string
}
