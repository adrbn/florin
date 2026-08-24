import { NextResponse } from 'next/server'
import { z } from 'zod'
import { revalidatePath } from 'next/cache'
import { mutations, queries } from '@/db/client'
import { authorizeApi } from '@/server/api-auth'

export const dynamic = 'force-dynamic'

/**
 * The Plan tab's feed and its one write.
 *
 * `getMonthPlan` already returns the whole envelope the screen needs — groups,
 * per-category assigned/spent/available, income and "ready to assign" — so the
 * route is a pass-through. The PUT is the only budgeting write a phone needs;
 * everything else on the web plan page (creating categories, copying a month)
 * is deliberately left there.
 */
function parseMonth(raw: string | null): { year: number; month: number } {
  if (raw && /^\d{4}-\d{2}$/.test(raw)) {
    const [y, m] = raw.split('-').map(Number)
    if (y && m && m >= 1 && m <= 12) return { year: y, month: m }
  }
  const now = new Date()
  return { year: now.getUTCFullYear(), month: now.getUTCMonth() + 1 }
}

const assignSchema = z.object({
  year: z.number().int().min(2000).max(2200),
  month: z.number().int().min(1).max(12),
  categoryId: z.string().min(1),
  amount: z.number().finite().min(0),
  note: z.string().trim().max(500).nullish(),
})

export async function GET(request: Request) {
  if (!(await authorizeApi(request))) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }
  const { year, month } = parseMonth(new URL(request.url).searchParams.get('month'))
  const plan = await queries.getMonthPlan(year, month)
  return NextResponse.json(plan, { headers: { 'cache-control': 'no-store' } })
}

export async function PUT(request: Request) {
  if (!(await authorizeApi(request))) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  let payload: unknown
  try {
    payload = await request.json()
  } catch {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 })
  }

  const parsed = assignSchema.safeParse(payload)
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`).join(', ') },
      { status: 400 },
    )
  }

  const result = await mutations.setCategoryAssigned(parsed.data)
  if (!result.success) {
    return NextResponse.json({ error: result.error ?? 'Rejected' }, { status: 422 })
  }
  revalidatePath('/plan')
  revalidatePath('/m/plan')
  return NextResponse.json({ ok: true })
}
