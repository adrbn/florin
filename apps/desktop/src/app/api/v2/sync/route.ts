import { NextResponse } from 'next/server'
import { revalidatePath } from 'next/cache'
import { syncAllConnections } from '@/server/banking/sync-all'

export const dynamic = 'force-dynamic'

/**
 * POST /api/v2/sync — pull every active bank connection, for the native client.
 *
 * Deliberately a separate route from `/api/banking/sync`, which the Electron
 * main process owns: this one reports the counts the phone puts on screen and
 * revalidates the v2 pages, and keeping them apart means a change for the tray
 * cannot quietly alter what the app receives.
 */
export async function POST() {
  try {
    const result = await syncAllConnections('manual')
    revalidatePath('/m')
    revalidatePath('/m/transactions')
    revalidatePath('/')
    return NextResponse.json({
      ok: result.errors.length === 0,
      connectionsSynced: result.connectionsSynced,
      accountsSynced: result.accountsSynced,
      transactionsInserted: result.transactionsInserted,
      error: result.errors.length > 0 ? result.errors.map((e) => e.message).join(' · ') : null,
    })
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Unknown error'
    return NextResponse.json({ ok: false, error: message }, { status: 500 })
  }
}
