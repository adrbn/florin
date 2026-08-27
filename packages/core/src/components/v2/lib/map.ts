import type {
  Account,
  CategoryGroupWithCategories,
  HoldingView,
  TransactionWithRelations,
} from '../../../types'
import type { V2Account, V2Category, V2Holding, V2Tx } from '../types'

/** Drizzle hands numerics back as strings on one driver and numbers on the other. */
function num(v: string | number | null | undefined): number {
  if (v === null || v === undefined) return 0
  const n = typeof v === 'number' ? v : Number(v)
  return Number.isFinite(n) ? n : 0
}

function iso(d: Date | string | null | undefined): string | null {
  if (!d) return null
  return d instanceof Date ? d.toISOString() : String(d)
}

/** Same conversion for a column the schema guarantees non-null. */
function isoRequired(d: Date | string): string {
  return d instanceof Date ? d.toISOString() : String(d)
}

export function mapTx(t: TransactionWithRelations): V2Tx {
  return {
    id: t.id,
    date: isoRequired(t.occurredAt),
    amount: num(t.amount),
    payee: t.payee,
    memo: t.memo,
    categoryId: t.categoryId,
    categoryName: t.category?.name ?? null,
    categoryEmoji: t.category?.emoji ?? null,
    accountId: t.accountId,
    accountName: t.account?.name ?? '',
    isTransfer: Boolean(t.transferPairId),
    needsReview: Boolean(t.needsReview),
    isPending: Boolean(t.isPending),
    isScheduled: t.status === 'scheduled',
  }
}

/**
 * @param remainingDebt Amortization liability for a loan account, from
 *   `getLoanLiabilities`. Omitting it for a loan falls back to its stored
 *   balance, which is only an approximation — pass it wherever a total is shown.
 */
export function mapAccount(a: Account, remainingDebt?: number): V2Account {
  const balance = num(a.currentBalance)
  const marketValue = num(a.marketValue)
  const isLoan = a.kind === 'loan'
  const debt = isLoan ? (remainingDebt ?? balance) : null
  const netContribution = !a.isIncludedInNetWorth ? 0 : isLoan ? -(debt ?? 0) : balance + marketValue
  return {
    id: a.id,
    name: a.name,
    kind: a.kind,
    institution: a.institution,
    currency: a.currency,
    balance,
    marketValue,
    total: balance + marketValue,
    netContribution,
    debt,
    isIncludedInNetWorth: a.isIncludedInNetWorth,
    isArchived: a.isArchived,
    syncProvider: a.syncProvider,
    lastSyncedAt: iso(a.lastSyncedAt),
    displayColor: a.displayColor,
    displayIcon: a.displayIcon,
    loan:
      isLoan
        ? {
            rate: a.loanInterestRate === null ? null : num(a.loanInterestRate),
            monthlyPayment: a.loanMonthlyPayment === null ? null : num(a.loanMonthlyPayment),
            termMonths: a.loanTermMonths,
            startDate: iso(a.loanStartDate),
          }
        : null,
  }
}

export function mapCategories(groups: CategoryGroupWithCategories[]): V2Category[] {
  return groups.flatMap((g) =>
    g.categories.map((c) => ({
      id: c.id,
      name: c.name,
      emoji: c.emoji,
      groupName: g.name,
      /*
       * The group's kind, not just its name.
       *
       * A client that stores these — the iOS app keeps its own copy of the
       * ledger — has no way to tell Revenus from Courses without it, and
       * rebuilding every group as an expense makes salaries count as negative
       * spending: plan income reads zero, no salary category is ever found,
       * and adjustments stop being excluded from the patrimony walk. The name
       * is a label; this is the meaning.
       */
      groupKind: g.kind,
    })),
  )
}

export function mapHolding(h: HoldingView): V2Holding {
  return {
    id: h.id,
    label: h.label,
    quantity: h.quantity,
    costBasis: h.costBasis,
    marketValue: h.marketValue,
    plusValue: h.plusValue,
    plusValuePct: h.plusValuePct,
    lastPrice: h.lastPrice,
    isStale: h.isStale,
  }
}
