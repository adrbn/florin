import { NextResponse } from 'next/server'
import { z } from 'zod'
import { revalidatePath } from 'next/cache'
import { mutations } from '@/db/client'

export const dynamic = 'force-dynamic'

/**
 * Act on several transactions at once.
 *
 * The review queue is the reason this exists: clearing it one sheet at a time
 * means a tap, a read, a tap and a dismissal per row, and nobody does that
 * thirty times. Approving is the only bulk verb the phone offers — bulk delete
 * is a lot of damage behind one button on a screen you hold in one hand.
 */
const bulkSchema = z.object({
  action: z.enum(['approve', 'categorize']),
  ids: z.array(z.string().min(1)).min(1).max(200),
  categoryId: z.string().nullish(),
})

export async function POST(request: Request) {
  let payload: unknown
  try {
    payload = await request.json()
  } catch {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 })
  }

  const parsed = bulkSchema.safeParse(payload)
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`).join(', ') },
      { status: 400 },
    )
  }

  const { action, ids, categoryId } = parsed.data
  const result =
    action === 'approve'
      ? await mutations.bulkApproveTransactions(ids)
      : await mutations.bulkUpdateTransactionCategory(ids, categoryId ?? null)

  if (!result.success) {
    return NextResponse.json({ error: result.error ?? 'Rejected' }, { status: 422 })
  }

  revalidatePath('/')
  revalidatePath('/m')
  revalidatePath('/transactions')
  revalidatePath('/m/transactions')
  revalidatePath('/m/review')

  const data = result.data as { approved?: number; updated?: number } | undefined
  return NextResponse.json({ ok: true, count: data?.approved ?? data?.updated ?? ids.length })
}
