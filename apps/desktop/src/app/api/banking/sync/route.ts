/**
 * POST /api/banking/sync — triggers a sync of all active bank connections.
 *
 * Called by the Electron main process (tray widget sync button, background
 * scheduler) via a localhost fetch. The sync logic runs inside the Next.js
 * server context where path aliases, drizzle, and Enable Banking modules
 * resolve correctly — unlike a direct dynamic import from the main process.
 */
import { type NextRequest, NextResponse } from 'next/server'
import type { SyncTrigger } from '@/server/banking/sync'
import { syncAllConnections } from '@/server/banking/sync-all'

export const dynamic = 'force-dynamic'

function parseTrigger(req: NextRequest): SyncTrigger {
  const raw = req.nextUrl.searchParams.get('trigger')
  if (raw === 'scheduler' || raw === 'initial') return raw
  return 'manual'
}

export async function POST(req: NextRequest): Promise<NextResponse> {
  try {
    const result = await syncAllConnections(parseTrigger(req))
    return NextResponse.json({
      success: result.errors.length === 0,
      data: {
        connectionsSynced: result.connectionsSynced,
        accountsSynced: result.accountsSynced,
        transactionsInserted: result.transactionsInserted,
      },
      error: result.errors.length > 0
        ? result.errors.map((e) => e.message).join('; ')
        : undefined,
    })
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Unknown error'
    return NextResponse.json({ success: false, error: message }, { status: 500 })
  }
}
