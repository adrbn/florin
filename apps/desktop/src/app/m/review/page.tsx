import { ReviewScreen } from '@florin/core/components/v2/screens/review'
import { mapCategories, mapTx } from '@florin/core/components/v2/lib/map'
import { queries } from '@/db/client'
import { approveTransaction, updateTransactionCategory } from '@/server/actions/transactions'

export const dynamic = 'force-dynamic'

export default async function V2Review() {
  const [transactions, groups] = await Promise.all([
    queries.listTransactions({ needsReviewOnly: true, limit: 200 }),
    queries.listCategoriesByGroup(),
  ])
  return (
    <ReviewScreen
      transactions={transactions.map(mapTx)}
      categories={mapCategories(groups)}
      actions={{ updateTransactionCategory, approveTransaction }}
    />
  )
}
