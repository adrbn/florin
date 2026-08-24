import { NextResponse } from 'next/server'
import { downsample, trimLeadingFlat } from '@florin/core/components/v2/lib/series'
import { mapAccount, mapCategories, mapTx } from '@florin/core/components/v2/lib/map'
import { V2_DICTS } from '@florin/core/components/v2/i18n'
import { projectGoal } from '@florin/core/lib/goal'
import { monthlyNetWorthTrend } from '@florin/core/lib/trend'
import { computeLoanLiability } from '@florin/core/lib/loan'
import { getLoanLiabilities } from '@florin/db-pg'
import { db, queries } from '@/db/client'
import { getAppConfig } from '@/lib/app-config'
import { APP_CURRENCY, getUserLocale } from '@/lib/locale'
import { auth } from '@/server/auth'
import { env } from '@/server/env'
import { countNeedsReview } from '@/server/actions/transactions'

export const dynamic = 'force-dynamic'

/** A phone chart is ~350pt wide; a year of daily points is wasted bytes. */
const HISTORY_MONTHS = 60
const MAX_POINTS = 400

/**
 * Read-only JSON feed for the native iOS client — the Postgres twin of the
 * desktop route.
 *
 * Auth accepts either the normal browser session or a bearer token, because a
 * native app has no NextAuth cookie to present. The token is opt-in: leave
 * `FLORIN_API_TOKEN` unset and the feed stays session-only, exactly as strict
 * as every other page on the deployment.
 */
async function authorize(request: Request): Promise<boolean> {
  const session = await auth()
  if (session?.user) return true

  const expected = env.FLORIN_API_TOKEN
  if (!expected) return false
  const header = request.headers.get('authorization') ?? ''
  const presented = header.startsWith('Bearer ') ? header.slice(7) : ''
  // Constant-time-ish: compare full length rather than bailing on first byte.
  if (presented.length !== expected.length) return false
  let diff = 0
  for (let i = 0; i < expected.length; i++) diff |= presented.charCodeAt(i) ^ expected.charCodeAt(i)
  return diff === 0
}

export async function GET(request: Request) {
  if (!(await authorize(request))) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

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
    locale,
    categoryGroups,
    connections,
  ] = await Promise.all([
    queries.getNetWorth(),
    queries.getPatrimonyTimeSeries(HISTORY_MONTHS),
    queries.getLeftToSpendThisMonth(),
    queries.getMonthBurn({ gross: true }),
    queries.getAvgMonthlyBurn(6),
    queries.getSavingsRates(),
    queries.getNetWorthAllocation(),
    queries.listAccounts(),
    queries.listTransactions({ limit: 12, excludeTransfers: false }),
    queries.getInvestmentSnapshot(),
    countNeedsReview(),
    getUserLocale(),
    queries.listCategoriesByGroup(),
    queries.listBankConnections(),
  ])

  const liabilities = await getLoanLiabilities(db, accounts)


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

  /*
   * Two curves, not one shifted copy.
   *
   * `getPatrimonyTimeSeries` seeds from today's *net* worth and walks back only
   * non-loan flows, so every point is `assets(t) − debt(today)`. Plotting
   * "gross" as `net + liability` would therefore be the identical curve moved
   * up by a constant — same shape, no information.
   *
   * The debt at each past date is recoverable: `computeLoanLiability` depends
   * only on how many instalments had been paid, so counting a loan's transfer
   * legs up to a date gives its balance then. That makes
   *   gross(t) = series(t) + debt(today)      (assets never involved the loan)
   *   net(t)   = gross(t) − debt(t)
   * and the net line now dips further in the past, when more was owed — which
   * is also a correctness fix: the old single curve subtracted today's debt
   * from the whole history.
   */
  const loanAccounts = accounts.filter((a) => a.kind === 'loan')
  const paymentDates = new Map<string, string[]>()
  await Promise.all(
    loanAccounts.map(async (loan) => {
      const rows = await queries.listTransactions({ accountId: loan.id, limit: 2000 })
      paymentDates.set(
        loan.id,
        rows
          .filter((r) => r.transferPairId)
          .map((r) => (r.occurredAt instanceof Date ? r.occurredAt.toISOString() : String(r.occurredAt)).slice(0, 10))
          .sort(),
      )
    }),
  )

  const debtToday = [...liabilities.values()].reduce((sum, l) => sum + l.remainingDebt, 0)

  const debtAt = (day: string): number =>
    loanAccounts.reduce((sum, loan) => {
      const dates = paymentDates.get(loan.id) ?? []
      // Sorted, so a linear count is fine at these sizes (a loan pays monthly).
      const paid = dates.filter((d) => d <= day).length
      return sum + computeLoanLiability(loan, paid).remainingDebt
    }, 0)

  const series = downsample(trimLeadingFlat(rawSeries), MAX_POINTS)
  const grossSeries = series.map((p) => ({ ...p, balance: p.balance + debtToday }))
  const netSeries =
    loanAccounts.length === 0
      ? series
      : series.map((p) => ({
          ...p,
          balance: p.balance + debtToday - debtAt(p.date.slice(0, 10)),
        }))

  const cfg = getAppConfig()
  const monthlyContribution =
    cfg.plannedMonthlyInvestment > 0 ? cfg.plannedMonthlyInvestment : snapshot.monthlyContribution
  const goal =
    cfg.goalTarget > 0 && (snapshot.investedValue > 0 || monthlyContribution > 0)
      ? projectGoal({
          currentValue: snapshot.investedValue,
          monthlyContribution,
          annualReturnPct: cfg.goalReturnPct,
          target: cfg.goalTarget,
        })
      : null

  /*
   * The native client renders its own screens, so it needs the same strings the
   * React screens use. Shipping the dictionary with the data — rather than
   * duplicating it in a String Catalog — is what makes the phone follow the
   * *app's* language setting instead of the device's, and means adding a native
   * screen never means translating anything twice. English underneath so a key
   * missing from a locale still renders a sentence.
   */
  const strings = { ...V2_DICTS.en, ...(V2_DICTS[locale] ?? {}) }

  const lastSyncedAt = accounts
    .map((a) => a.lastSyncedAt)
    .filter((d): d is Date => d instanceof Date)
    .sort((a, b) => b.getTime() - a.getTime())[0]

  return NextResponse.json(
    {
      generatedAt: new Date().toISOString(),
      locale,
      strings,
      lastSyncedAt: lastSyncedAt ? lastSyncedAt.toISOString() : null,
      bankSyncConfigured: connections.length > 0,
      currency: APP_CURRENCY,
      netWorth,
      monthlyTrend: monthlyNetWorthTrend(rawSeries.slice(-366)),
      series,
      grossSeries,
      netSeries,
      leftToSpend,
      burnThisMonth,
      burnAvg6,
      savings,
      allocation,
      goal,
      reviewCount,
      incomeIsEstimated,
      accounts: accounts.map((a) => mapAccount(a, liabilities.get(a.id)?.remainingDebt)),
      categories: mapCategories(categoryGroups),
      recent: recent.map(mapTx),
    },
    { headers: { 'cache-control': 'no-store' } },
  )
}
