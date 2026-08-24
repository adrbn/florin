import { ActivityScreen } from '@florin/core/components/v2/screens/activity'
import { mapAccount, mapCategories, mapTx } from '@florin/core/components/v2/lib/map'
import type { TransactionDirection } from '@florin/core/types'
import { queries } from '@/db/client'
import {
  approveTransaction,
  softDeleteTransaction,
  updateTransaction,
  updateTransactionCategory,
} from '@/server/actions/transactions'

export const dynamic = 'force-dynamic'

const PAGE_SIZE = 50

function isoDate(raw: string | undefined): string {
  return raw && /^\d{4}-\d{2}-\d{2}$/.test(raw) ? raw : ''
}

export default async function V2Activity({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | undefined>>
}) {
  const sp = await searchParams

  const q = sp.q?.trim() ?? ''
  const accountId = sp.accountId ?? ''
  const categoryId = sp.categoryId ?? ''
  const direction: TransactionDirection =
    sp.direction === 'expense' || sp.direction === 'income' ? sp.direction : 'all'
  const excludeTransfers = sp.excludeTransfers === '1'
  const needsReview = sp.needsReview === '1'
  const from = isoDate(sp.from)
  const to = isoDate(sp.to)
  const page = Math.max(1, Number(sp.page) || 1)

  const options = {
    limit: PAGE_SIZE,
    offset: (page - 1) * PAGE_SIZE,
    payeeSearch: q || undefined,
    accountId: accountId || undefined,
    categoryId: categoryId || undefined,
    direction,
    excludeTransfers,
    needsReviewOnly: needsReview || undefined,
    // The query layer takes ISO datetimes; widen `to` to the end of that day so
    // a same-day from/to pair isn't an empty window.
    startDate: from ? new Date(`${from}T00:00:00`).toISOString() : undefined,
    endDate: to ? new Date(`${to}T23:59:59.999`).toISOString() : undefined,
  }

  const [transactions, total, accounts, groups, reviewCount] = await Promise.all([
    queries.listTransactions(options),
    queries.countTransactions(options),
    queries.listAccounts(),
    queries.listCategoriesByGroup(),
    // The queue size, independent of what is filtered right now — the chip has
    // to say how much work exists, not how much of it is currently on screen.
    queries.countNeedsReview(),
  ])

  return (
    <ActivityScreen
      actions={{ updateTransactionCategory, softDeleteTransaction, approveTransaction, updateTransaction }}
      data={{
        transactions: transactions.map(mapTx),
        total,
        pageSize: PAGE_SIZE,
        filters: {
          q,
          accountId,
          categoryId,
          direction,
          excludeTransfers,
          needsReview,
          from,
          to,
          page,
        },
        reviewCount,
        accounts: accounts.map(mapAccount),
        categories: mapCategories(groups),
      }}
    />
  )
}
