import { NextResponse } from 'next/server'
import { z } from 'zod'
import { revalidatePath } from 'next/cache'
import { mutations } from '@/db/client'
import { authorizeApi } from '@/server/api-auth'

export const dynamic = 'force-dynamic'

/**
 * Edit, categorise, approve or delete one transaction from the phone.
 *
 * The native Activity tab doubles as the review queue (it is the same list with
 * `needsReview=1`), so it needs the same four verbs the web rows have. Each one
 * goes through the same mutation the browser calls, which is what keeps balance
 * recomputation, transfer pairing and the categorisation rules identical
 * regardless of which client touched the row.
 */
const patchSchema = z
  .object({
    categoryId: z.string().nullish(),
    approve: z.boolean().optional(),
    payee: z.string().trim().min(1).max(200).optional(),
    memo: z.string().trim().max(500).nullish(),
    amount: z.number().finite().optional(),
    occurredAt: z.iso.datetime().optional(),
  })
  .refine((b) => Object.keys(b).length > 0, 'Nothing to change')

function failed(result: { success: boolean; error?: string | null }) {
  return result.success ? null : NextResponse.json({ error: result.error ?? 'Rejected' }, { status: 422 })
}

function revalidate() {
  revalidatePath('/')
  revalidatePath('/m')
  revalidatePath('/transactions')
  revalidatePath('/m/transactions')
  revalidatePath('/m/review')
}

async function applyPatch(id: string, body: z.infer<typeof patchSchema>) {
  // Order matters: edit the fields first, then categorise, then approve — an
  // approve that ran before the category was set would file the row away
  // uncategorised, which is the one outcome the review queue exists to prevent.
  const fields = {
    payee: body.payee,
    memo: body.memo,
    amount: body.amount,
    occurredAt: body.occurredAt ? new Date(body.occurredAt) : undefined,
  }
  if (Object.values(fields).some((v) => v !== undefined)) {
    const result = await mutations.updateTransaction(id, fields)
    if (!result.success) return result
  }
  if (body.categoryId !== undefined) {
    const result = await mutations.updateTransactionCategory(id, body.categoryId ?? null)
    if (!result.success) return result
  }
  if (body.approve) {
    const result = await mutations.approveTransaction(id)
    if (!result.success) return result
  }
  return { success: true as const }
}

export async function PATCH(request: Request, { params }: { params: Promise<{ id: string }> }) {
  if (!(await authorizeApi(request))) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }
  const { id } = await params

  let payload: unknown
  try {
    payload = await request.json()
  } catch {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 })
  }

  const parsed = patchSchema.safeParse(payload)
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`).join(', ') },
      { status: 400 },
    )
  }

  const rejected = failed(await applyPatch(id, parsed.data))
  if (rejected) return rejected
  revalidate()
  return NextResponse.json({ ok: true })
}

export async function DELETE(request: Request, { params }: { params: Promise<{ id: string }> }) {
  if (!(await authorizeApi(request))) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }
  const { id } = await params
  const rejected = failed(await mutations.softDeleteTransaction(id))
  if (rejected) return rejected
  revalidate()
  return NextResponse.json({ ok: true })
}
