/**
 * POST /api/pricing/refresh — refreshes security price quotes for all holdings.
 *
 * Called by the Electron main process (6h scheduler + warmup) via a localhost
 * HTTPS fetch. The refresh logic runs inside the Next.js server context where
 * path aliases, drizzle, and the pricing client resolve correctly — unlike a
 * direct dynamic import from the main process (CLAUDE.md rule).
 */
import { NextResponse } from 'next/server'
import { refreshPriceQuotes } from '@/server/pricing/refresh'

export const dynamic = 'force-dynamic'

export async function POST(): Promise<NextResponse> {
  try {
    const result = await refreshPriceQuotes()
    return NextResponse.json({ success: true, data: result })
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Unknown error'
    return NextResponse.json({ success: false, error: message }, { status: 500 })
  }
}
