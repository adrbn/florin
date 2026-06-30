import type { PriceQuote } from './types'

/**
 * Fetch a single quote from Yahoo Finance's unauthenticated chart endpoint.
 *
 *   GET https://query1.finance.yahoo.com/v8/finance/chart/{symbol}?range=1d&interval=1d
 *
 * Reads `chart.result[0].meta.regularMarketPrice` and `…meta.currency`.
 *
 * Returns `null` on ANY failure (network error, non-200, malformed JSON,
 * missing/invalid price, abort/timeout). It NEVER throws — the refresh loop
 * must survive one bad symbol. Only the symbol leaves the machine (no PII).
 */
export async function fetchYahooQuote(symbol: string): Promise<PriceQuote | null> {
  const url = `https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(
    symbol,
  )}?range=1d&interval=1d`
  const ctrl = new AbortController()
  const timer = setTimeout(() => ctrl.abort(), 8000)
  try {
    const res = await fetch(url, { cache: 'no-store', signal: ctrl.signal })
    if (!res.ok) return null
    const json = (await res.json()) as unknown
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const meta = (json as any)?.chart?.result?.[0]?.meta
    const price = meta?.regularMarketPrice
    if (typeof price !== 'number' || !Number.isFinite(price)) return null
    return {
      symbol,
      price,
      currency: typeof meta.currency === 'string' ? meta.currency : 'EUR',
      fetchedAt: new Date().toISOString(),
    }
  } catch {
    return null
  } finally {
    clearTimeout(timer)
  }
}
