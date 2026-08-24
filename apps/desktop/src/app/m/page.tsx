import { OverviewScreen } from '@florin/core/components/v2/screens/overview'
import { downsample, trimLeadingFlat } from '@florin/core/components/v2/lib/series'
import { mapAccount, mapCategories, mapTx } from '@florin/core/components/v2/lib/map'
import { projectGoal } from '@florin/core/lib/goal'
import { monthlyNetWorthTrend } from '@florin/core/lib/trend'
import { getLoanLiabilities } from '@florin/db-sqlite'
import { db, queries } from '@/db/client'
import { getAppConfig } from '@/lib/app-config'
import {
  approveTransaction,
  countNeedsReview,
  softDeleteTransaction,
  updateTransaction,
  updateTransactionCategory,
} from '@/server/actions/transactions'
import { syncAllBanks } from '@/server/actions/banking'

export const dynamic = 'force-dynamic'

/** Five years of daily points, thinned to something a 350px chart can use. */
const HISTORY_MONTHS = 60
const MAX_POINTS = 400

export default async function V2Overview() {
  const [
    netWorth,
    rawSeries,
    leftToSpend,
    burnThisMonth,
    burnAvg6,
    savings,
    allocation,
    accounts,
    recent,
    snapshot,
    reviewCount,
    connections,
    categoryGroups,
  ] = await Promise.all([
    queries.getNetWorth(),
    queries.getPatrimonyTimeSeries(HISTORY_MONTHS),
    queries.getLeftToSpendThisMonth(),
    queries.getMonthBurn({ gross: true }),
    queries.getAvgMonthlyBurn(6),
    queries.getSavingsRates(),
    queries.getNetWorthAllocation(),
    queries.listAccounts(),
    queries.listTransactions({ limit: 6, excludeTransfers: false }),
    queries.getInvestmentSnapshot(),
    countNeedsReview(),
    queries.listBankConnections(),
    queries.listCategoriesByGroup(),
  ])

  const series = downsample(trimLeadingFlat(rawSeries), MAX_POINTS)

  // A loan's stored balance is not its liability — getNetWorth derives the debt
  // from the amortization schedule. Feed the same figure to the account rows so
  // the list can never disagree with the headline above it.
  const liabilities = await getLoanLiabilities(db, accounts)
  const mappedAccounts = accounts.map((a) => mapAccount(a, liabilities.get(a.id)?.remainingDebt))


  /*
   * Has this month's salary actually landed? `getLeftToSpendThisMonth`
   * substitutes last month's when it has not, which keeps "left to spend"
   * useful before payday but leaves the figure describing a month that has not
   * happened. One count tells the UI whether to say so.
   */
  const monthStart = new Date(new Date().getFullYear(), new Date().getMonth(), 1)
  const incomeIsEstimated = leftToSpend.salaryCategoryId
    ? (await queries.countTransactions({
        categoryId: leftToSpend.salaryCategoryId,
        startDate: monthStart.toISOString(),
        direction: 'income',
      })) === 0
    : false

  const cfg = await getAppConfig()
  const monthlyContribution =
    cfg.plannedMonthlyInvestment > 0 ? cfg.plannedMonthlyInvestment : snapshot.monthlyContribution
  const goal =
    snapshot.investedValue > 0 || monthlyContribution > 0
      ? projectGoal({
          currentValue: snapshot.investedValue,
          monthlyContribution,
          annualReturnPct: cfg.goalReturnPct,
          target: cfg.goalTarget,
        })
      : null

  const lastSyncedAt = accounts
    .map((a) => a.lastSyncedAt)
    .filter((d): d is Date => d instanceof Date)
    .sort((a, b) => b.getTime() - a.getTime())[0]

  return (
    <OverviewScreen
      onSyncAll={syncAllBanks}
      categories={mapCategories(categoryGroups)}
      txActions={{ updateTransactionCategory, softDeleteTransaction, approveTransaction, updateTransaction }}
      data={{
        netWorth,
        series,
        leftToSpend,
        burnThisMonth,
        burnAvg6,
        savings,
        allocation,
        accounts: mappedAccounts,
        recent: recent.map(mapTx),
        goal,
        reviewCount,
        incomeIsEstimated,
        monthlyTrend: monthlyNetWorthTrend(rawSeries.slice(-366)),
        lastSyncedAt: lastSyncedAt ? lastSyncedAt.toISOString() : null,
        hasBankSync: connections.length > 0,
      }}
    />
  )
}
