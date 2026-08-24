import { notFound } from 'next/navigation'
import { AccountDetailScreen } from '@florin/core/components/v2/screens/account-detail'
import {
  mapAccount,
  mapCategories,
  mapHolding,
  mapTx,
} from '@florin/core/components/v2/lib/map'
import { getLoanLiabilities } from '@florin/db-pg'
import { db, queries } from '@/db/client'
import {
  approveTransaction,
  softDeleteTransaction,
  updateTransaction,
  updateTransactionCategory,
} from '@/server/actions/transactions'

export const dynamic = 'force-dynamic'

export default async function V2AccountDetail({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
  const account = await queries.getAccountById(id)
  if (!account) notFound()

  const isBroker = account.kind === 'broker_portfolio' || account.kind === 'broker_cash'
  const liabilities = await getLoanLiabilities(db, [account])
  const [transactions, holdings, valuation, categoryGroups] = await Promise.all([
    queries.listTransactions({ accountId: id, limit: 120 }),
    isBroker ? queries.listHoldings(id) : Promise.resolve([]),
    isBroker ? queries.getPortfolioValuation(id) : Promise.resolve(null),
    queries.listCategoriesByGroup(),
  ])

  return (
    <AccountDetailScreen
      categories={mapCategories(categoryGroups)}
      txActions={{ updateTransactionCategory, softDeleteTransaction, approveTransaction, updateTransaction }}
      data={{
        account: mapAccount(account, liabilities.get(account.id)?.remainingDebt),
        transactions: transactions.map(mapTx),
        holdings: holdings.map(mapHolding),
        valuation: valuation
          ? {
              marketValue: valuation.marketValue,
              costBasis: valuation.costBasis,
              plusValue: valuation.plusValue,
              cash: valuation.cash,
            }
          : null,
      }}
    />
  )
}
