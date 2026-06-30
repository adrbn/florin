/**
 * POST /api/pricing/refresh — refreshes security price quotes for all holdings.
 *
 * Exposed for parity with the desktop app (where the Electron main process
 * calls this over localhost). On web it's also reachable directly; the heavy
 * lifting lives in the server module so path aliases and drizzle resolve.
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
