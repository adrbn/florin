import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { fetchQuote, fetchYahooQuote } from '@florin/core/pricing'

// A well-formed Yahoo chart response, trimmed to the fields the client reads.
function goodResponse(price = 28.41, currency = 'EUR', symbol = 'WPEA.PA') {
  return {
    chart: {
      result: [
        {
          meta: {
            regularMarketPrice: price,
            currency,
            symbol,
          },
        },
      ],
      error: null,
    },
  }
}

function mockFetchOnce(opts: {
  ok?: boolean
  status?: number
  json?: unknown
  throws?: boolean
}) {
  const fetchMock = vi.fn(async () => {
    if (opts.throws) throw new Error('network down')
    return {
      ok: opts.ok ?? true,
      status: opts.status ?? 200,
      json: async () => {
        if (opts.json === undefined) throw new SyntaxError('Unexpected token')
        return opts.json
      },
    } as unknown as Response
  })
  vi.stubGlobal('fetch', fetchMock)
  return fetchMock
}

describe('fetchYahooQuote', () => {
  afterEach(() => {
    vi.unstubAllGlobals()
    vi.restoreAllMocks()
  })

  it('parses a good fixture into a PriceQuote', async () => {
    mockFetchOnce({ json: goodResponse(28.41, 'EUR', 'WPEA.PA') })
    const quote = await fetchYahooQuote('WPEA.PA')
    expect(quote).not.toBeNull()
    expect(quote?.price).toBe(28.41)
    expect(quote?.currency).toBe('EUR')
    expect(quote?.symbol).toBe('WPEA.PA')
    expect(typeof quote?.fetchedAt).toBe('string')
    // fetchedAt is a valid ISO timestamp
    expect(Number.isNaN(Date.parse(quote!.fetchedAt))).toBe(false)
  })

  it('sends only the symbol in the request URL (no PII)', async () => {
    const fetchMock = mockFetchOnce({ json: goodResponse() })
    await fetchYahooQuote('WPEA.PA')
    expect(fetchMock).toHaveBeenCalledTimes(1)
    const calledUrl = String(fetchMock.mock.calls[0]![0])
    expect(calledUrl).toContain('WPEA.PA')
    expect(calledUrl).toContain('query1.finance.yahoo.com')
    expect(calledUrl).toContain('/v8/finance/chart/')
    // request options request a fresh (uncached) fetch
    const opts = fetchMock.mock.calls[0]![1] as RequestInit
    expect(opts.cache).toBe('no-store')
  })

  it('url-encodes symbols that need it', async () => {
    const fetchMock = mockFetchOnce({ json: goodResponse(10, 'EUR', 'BRK B') })
    await fetchYahooQuote('BRK B')
    const calledUrl = String(fetchMock.mock.calls[0]![0])
    expect(calledUrl).toContain('BRK%20B')
  })

  it('returns null on a non-200 response', async () => {
    mockFetchOnce({ ok: false, status: 404, json: goodResponse() })
    expect(await fetchYahooQuote('NOPE')).toBeNull()
  })

  it('returns null on malformed JSON', async () => {
    mockFetchOnce({ json: undefined }) // json() throws
    expect(await fetchYahooQuote('WPEA.PA')).toBeNull()
  })

  it('returns null when regularMarketPrice is missing', async () => {
    mockFetchOnce({
      json: { chart: { result: [{ meta: { currency: 'EUR' } }], error: null } },
    })
    expect(await fetchYahooQuote('WPEA.PA')).toBeNull()
  })

  it('returns null when regularMarketPrice is not a finite number', async () => {
    mockFetchOnce({
      json: {
        chart: { result: [{ meta: { regularMarketPrice: 'oops', currency: 'EUR' } }] },
      },
    })
    expect(await fetchYahooQuote('WPEA.PA')).toBeNull()
  })

  it('returns null when the result array is empty', async () => {
    mockFetchOnce({ json: { chart: { result: [], error: null } } })
    expect(await fetchYahooQuote('WPEA.PA')).toBeNull()
  })

  it('returns null (never throws) when fetch rejects', async () => {
    mockFetchOnce({ throws: true })
    await expect(fetchYahooQuote('WPEA.PA')).resolves.toBeNull()
  })

  it('falls back to EUR when meta.currency is absent', async () => {
    mockFetchOnce({
      json: { chart: { result: [{ meta: { regularMarketPrice: 5 } }] } },
    })
    const quote = await fetchYahooQuote('X')
    expect(quote?.currency).toBe('EUR')
  })
})

describe('fetchQuote (provider dispatch)', () => {
  afterEach(() => {
    vi.unstubAllGlobals()
    vi.restoreAllMocks()
  })

  it("provider 'none' returns null without making any fetch", async () => {
    const fetchMock = mockFetchOnce({ json: goodResponse() })
    const quote = await fetchQuote({ provider: 'none' }, 'WPEA.PA')
    expect(quote).toBeNull()
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it("provider 'yahoo' dispatches to the Yahoo client", async () => {
    const fetchMock = mockFetchOnce({ json: goodResponse(12.5, 'EUR', 'WPEA.PA') })
    const quote = await fetchQuote({ provider: 'yahoo' }, 'WPEA.PA')
    expect(fetchMock).toHaveBeenCalledTimes(1)
    expect(quote?.price).toBe(12.5)
    const calledUrl = String(fetchMock.mock.calls[0]![0])
    expect(calledUrl).toContain('WPEA.PA')
  })

  it("provider 'yahoo' propagates a null on fetch failure", async () => {
    mockFetchOnce({ ok: false, status: 500, json: goodResponse() })
    expect(await fetchQuote({ provider: 'yahoo' }, 'WPEA.PA')).toBeNull()
  })
})
