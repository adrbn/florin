import { and, asc, eq, isNotNull, isNull, sql } from 'drizzle-orm'
import type { HoldingView, PortfolioValuation } from '@florin/core/types'
import type { SqliteDB } from '../client'
import { accounts, holdings, transactions } from '../schema'

// SQLite twin of db-pg/queries/portfolio.ts. quantity/costBasis/lastPrice are
// real numbers; lastPriceAt is an ISO string.

const STALE_MS = 48 * 60 * 60 * 1000

function toHoldingView(row: typeof holdings.$inferSelect): HoldingView {
  const quantity = Number(row.quantity)
  const costBasis = Number(row.costBasis)
  const lastPrice = row.lastPrice === null || row.lastPrice === undefined ? null : Number(row.lastPrice)
  const marketValue = quantity * (lastPrice ?? 0)
  const plusValue = marketValue - costBasis
  const plusValuePct = costBasis > 0 ? (plusValue / costBasis) * 100 : null
  const lastPriceAtMs = row.lastPriceAt ? new Date(row.lastPriceAt).getTime() : null
  return {
    id: row.id,
    accountId: row.accountId,
    label: row.label,
    isin: row.isin,
    quoteSymbol: row.quoteSymbol,
    quantity,
    costBasis,
    currency: row.currency,
    lastPrice,
    lastPriceAt: row.lastPriceAt ? new Date(row.lastPriceAt).toISOString() : null,
    marketValue,
    plusValue,
    plusValuePct,
    isStale: lastPriceAtMs !== null && !Number.isNaN(lastPriceAtMs) && Date.now() - lastPriceAtMs > STALE_MS,
  }
}

export async function listHoldings(db: SqliteDB, accountId: string): Promise<HoldingView[]> {
  const rows = await db
    .select()
    .from(holdings)
    .where(eq(holdings.accountId, accountId))
    .orderBy(asc(holdings.createdAt))
  return rows.map(toHoldingView)
}

export async function getPortfolioValuation(
  db: SqliteDB,
  accountId: string,
): Promise<PortfolioValuation> {
  const acc = await db.query.accounts.findFirst({
    where: eq(accounts.id, accountId),
    columns: { marketValue: true, currentBalance: true },
  })
  const marketValue = acc ? Number(acc.marketValue) : 0
  const cash = acc ? Number(acc.currentBalance) : 0

  const [cbRow] = await db
    .select({ total: sql<number>`COALESCE(SUM(${holdings.costBasis}), 0)` })
    .from(holdings)
    .where(eq(holdings.accountId, accountId))
  const costBasis = Number(cbRow?.total ?? 0)

  const [vRow] = await db
    .select({ total: sql<number>`COALESCE(SUM(${transactions.amount}), 0)` })
    .from(transactions)
    .where(
      and(
        eq(transactions.accountId, accountId),
        isNotNull(transactions.transferPairId),
        sql`${transactions.amount} > 0`,
        isNull(transactions.deletedAt),
        eq(transactions.status, 'cleared'),
      ),
    )
  const verse = Number(vRow?.total ?? 0)

  const plusValue = marketValue - costBasis
  const marche = marketValue + cash - verse
  return { marketValue, costBasis, plusValue, cash, verse, marche }
}

/** All holdings that have a quote symbol — the price-refresh work-list. */
export async function listHoldingsToPrice(
  db: SqliteDB,
): Promise<Array<{ id: string; accountId: string; quoteSymbol: string }>> {
  const rows = await db
    .select({
      id: holdings.id,
      accountId: holdings.accountId,
      quoteSymbol: holdings.quoteSymbol,
    })
    .from(holdings)
    .where(isNotNull(holdings.quoteSymbol))
  return rows.filter((r): r is { id: string; accountId: string; quoteSymbol: string } =>
    Boolean(r.quoteSymbol),
  )
}
