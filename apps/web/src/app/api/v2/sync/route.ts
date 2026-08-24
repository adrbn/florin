import { NextResponse } from 'next/server'
import { revalidatePath } from 'next/cache'
import { syncAllBanks } from '@/server/actions/banking'
import { auth } from '@/server/auth'
import { env } from '@/server/env'

export const dynamic = 'force-dynamic'

/** Same session-or-bearer rule as the read feed. */
async function authorize(request: Request): Promise<boolean> {
  const session = await auth()
  if (session?.user) return true
  const expected = env.FLORIN_API_TOKEN
  if (!expected) return false
  const header = request.headers.get('authorization') ?? ''
  const presented = header.startsWith('Bearer ') ? header.slice(7) : ''
  if (presented.length !== expected.length) return false
  let diff = 0
  for (let i = 0; i < expected.length; i++) diff |= presented.charCodeAt(i) ^ expected.charCodeAt(i)
  return diff === 0
}

export async function POST(request: Request) {
  if (!(await authorize(request))) {
    return NextResponse.json({ ok: false, error: 'Unauthorized' }, { status: 401 })
  }

  const result = await syncAllBanks()
  revalidatePath('/m')
  revalidatePath('/m/transactions')

  return NextResponse.json({
    ok: result.success,
    connectionsSynced: result.data?.connectionsSynced ?? 0,
    accountsSynced: result.data?.accountsSynced ?? 0,
    transactionsInserted: result.data?.transactionsInserted ?? 0,
    error: result.error ?? null,
  })
}
