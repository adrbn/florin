import { NextResponse } from 'next/server'
import { mapHolding } from '@florin/core/components/v2/lib/map'
import { queries } from '@/db/client'

export const dynamic = 'force-dynamic'

/**
 * One wrapper's valuation and its positions.
 *
 * Kept off the dashboard feed on purpose: holdings only matter once you open a
 * broker account, and folding them into `/api/v2/overview` would make every
 * launch pay for a query most launches never use.
 *
 * `marche` is the honest performance figure here — market value plus idle cash
 * minus everything transferred in — because a PEA's gain is not
 * `marketValue − costBasis` when part of the wrapper is uninvested cash.
 */

export async function GET(_request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const [valuation, holdings] = await Promise.all([
    queries.getPortfolioValuation(id),
    queries.listHoldings(id),
  ])
  return NextResponse.json(
    { valuation, holdings: holdings.map(mapHolding) },
    { headers: { 'cache-control': 'no-store' } },
  )
}
