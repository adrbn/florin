import { fetchQuote } from '@florin/core/pricing'
import type { PriceRefreshResult } from '@florin/core/types'
import { listHoldingsToPrice, applyHoldingQuoteMutation, recomputeMarketValue } from '@florin/db-pg'
import { db } from '@/db/client'
import { getPricingConfig } from './config'

/**
 * Fetch fresh quotes for every holding that has a quote symbol, store each on
 * its holding row, then recompute the market value of each affected
 * broker_portfolio account.
 *
 * Resilient by design: a `'none'` provider short-circuits with zero network
 * calls; a per-symbol fetch failure (`null`) is counted as `failed` and leaves
 * the holding's previous price untouched (stale, not zeroed); one bad symbol
 * never aborts the loop. Safe to call fire-and-forget on every dashboard load.
 */
export async function refreshPriceQuotes(): Promise<PriceRefreshResult> {
  const config = getPricingConfig()
  if (config.provider === 'none') {
    return { fetched: 0, failed: 0, skipped: true }
  }

  const holdings = await listHoldingsToPrice(db)

  let fetched = 0
  let failed = 0
  const affectedAccountIds = new Set<string>()

  for (const holding of holdings) {
    const quote = await fetchQuote(config, holding.quoteSymbol)
    if (!quote) {
      failed += 1
      continue
    }
    const accountId = await applyHoldingQuoteMutation(
      db,
      holding.id,
      quote.price,
      quote.fetchedAt,
    )
    if (accountId) {
      fetched += 1
      affectedAccountIds.add(accountId)
    } else {
      failed += 1
    }
  }

  for (const accountId of affectedAccountIds) {
    await recomputeMarketValue(db, accountId)
  }

  return { fetched, failed, skipped: false }
}
