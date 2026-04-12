import { and, inArray, isNotNull, isNull, sql } from 'drizzle-orm'
import { computeLoanLiability, type LoanLiability } from '@florin/core/lib/loan'
import type { SqliteDB } from '../client'
import { transactions } from '../schema'

/**
 * Shape the helper needs from an account row. Kept structural so any caller
 * (server actions, server queries, server components) can pass its own Drizzle
 * row or a projected subset without an import cycle back to the action layer.
 */
export interface LoanLiabilityInputAccount {
  id: string
  kind: string
  loanOriginalPrincipal: string | number | null
  loanInterestRate: string | number | null
  loanTermMonths: number | null
  loanMonthlyPayment: string | number | null
  loanStartDate: Date | string | null
  currentBalance?: string | number | null
}

/**
 * Compute amortization-based liability for every loan account in the input
 * list in a single round trip to the DB. Returns a Map keyed by account id.
 */
export async function getLoanLiabilities(
  db: SqliteDB,
  accountRows: ReadonlyArray<LoanLiabilityInputAccount>,
): Promise<Map<string, LoanLiability>> {
  const result = new Map<string, LoanLiability>()
  const loanAccounts = accountRows.filter((a) => a.kind === 'loan')
  if (loanAccounts.length === 0) return result

  // Single GROUP BY query gets us all payment counts at once.
  const loanIds = loanAccounts.map((a) => a.id)
  const rows = await db
    .select({
      accountId: transactions.accountId,
      count: sql<number>`COUNT(*)`,
    })
    .from(transactions)
    .where(
      and(
        inArray(transactions.accountId, loanIds),
        isNotNull(transactions.transferPairId),
        isNull(transactions.deletedAt),
      ),
    )
    .groupBy(transactions.accountId)

  const counts = new Map<string, number>()
  for (const r of rows) {
    counts.set(r.accountId, Number(r.count))
  }

  for (const a of loanAccounts) {
    const paid = counts.get(a.id) ?? 0
    result.set(a.id, computeLoanLiability(a, paid))
  }
  return result
}
