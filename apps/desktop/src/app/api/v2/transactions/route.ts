import { NextResponse } from 'next/server'
import { z } from 'zod'
import { revalidatePath } from 'next/cache'
import { mapAccount, mapCategories, mapTx } from '@florin/core/components/v2/lib/map'
import type { TransactionDirection } from '@florin/core/types'
import { getLoanLiabilities } from '@florin/db-sqlite'
import { db, mutations, queries } from '@/db/client'
import { countNeedsReview } from '@/server/actions/transactions'

export const dynamic = 'force-dynamic'

/**
 * The one write the phone needs: record a transaction.
 *
 * It goes through the same `mutations.addTransaction` the web form uses, so
 * balance recomputation, transfer pairing and categorisation rules all behave
 * identically no matter which client typed it.
 */
const bodySchema = z.object({
  accountId: z.string().min(1),
  /** Signed. The client decides the sign from its expense/income toggle. */
  amount: z.number().finite().refine((n) => n !== 0, 'Amount must not be zero'),
  payee: z.string().trim().min(1).max(200),
  occurredAt: z.iso.datetime(),
  memo: z.string().trim().max(500).nullish(),
  categoryId: z.string().nullish(),
})

export async function POST(request: Request) {
  let payload: unknown
  try {
    payload = await request.json()
  } catch {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 })
  }

  const parsed = bodySchema.safeParse(payload)
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`).join(', ') },
      { status: 400 },
    )
  }

  const input = parsed.data
  const result = await mutations.addTransaction({
    accountId: input.accountId,
    amount: input.amount,
    payee: input.payee,
    occurredAt: new Date(input.occurredAt),
    memo: input.memo ?? null,
    categoryId: input.categoryId ?? null,
  })

  if (!result.success) {
    return NextResponse.json({ error: result.error ?? 'Could not save' }, { status: 422 })
  }

  // Keep the browser surfaces in step with what the phone just wrote.
  revalidatePath('/')
  revalidatePath('/m')
  revalidatePath('/transactions')
  revalidatePath('/m/transactions')

  return NextResponse.json({ ok: true, id: result.data?.id ?? null }, { status: 201 })
}

/**
 * Paginated transaction list for the native client.
 *
 * Same options object the `/m/transactions` page builds from its search
 * params, so a filter behaves identically whether it was typed in the browser
 * or tapped on the phone, and `mapTx` keeps the wire shape identical to the one
 * the React rows already consume.
 */
const MAX_LIMIT = 100

function isoDate(raw: string | null): string {
  return raw && /^\d{4}-\d{2}-\d{2}$/.test(raw) ? raw : ''
}

function listOptions(url: URL) {
  const sp = url.searchParams
  const from = isoDate(sp.get('from'))
  const to = isoDate(sp.get('to'))
  const direction = sp.get('direction')
  return {
    limit: Math.min(MAX_LIMIT, Math.max(1, Number(sp.get('limit')) || 50)),
    offset: Math.max(0, Number(sp.get('offset')) || 0),
    payeeSearch: sp.get('q')?.trim() || undefined,
    accountId: sp.get('accountId') || undefined,
    categoryId: sp.get('categoryId') || undefined,
    direction: (direction === 'expense' || direction === 'income'
      ? direction
      : 'all') as TransactionDirection,
    excludeTransfers: sp.get('excludeTransfers') === '1',
    needsReviewOnly: sp.get('needsReview') === '1' || undefined,
    // The query layer takes ISO datetimes; widen `to` to the end of that day so
    // a same-day from/to pair isn't an empty window.
    startDate: from ? new Date(`${from}T00:00:00`).toISOString() : undefined,
    endDate: to ? new Date(`${to}T23:59:59.999`).toISOString() : undefined,
  }
}

export async function GET(request: Request) {
  const options = listOptions(new URL(request.url))

  const [transactions, total, accounts, groups, reviewCount] = await Promise.all([
    queries.listTransactions(options),
    queries.countTransactions(options),
    queries.listAccounts(),
    queries.listCategoriesByGroup(),
    countNeedsReview(),
  ])
  const liabilities = await getLoanLiabilities(db, accounts)

  return NextResponse.json(
    {
      total,
      reviewCount,
      transactions: transactions.map(mapTx),
      accounts: accounts.map((a) => mapAccount(a, liabilities.get(a.id)?.remainingDebt)),
      categories: mapCategories(groups),
    },
    { headers: { 'cache-control': 'no-store' } },
  )
}
