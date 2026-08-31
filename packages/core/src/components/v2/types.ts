import type {
  ActionResult,
  AddTransactionInput,
  AddTransferInput,
  SetCategoryAssignedInput,
} from '../../types'

/**
 * Serializable view models.
 *
 * The screens are client components, so everything they receive crosses the
 * RSC boundary. Drizzle rows carry `Date` objects and numeric-as-string
 * columns whose shape differs between the Postgres and SQLite drivers; mapping
 * to these plain types in the page adapter is what lets one set of screens
 * serve both apps without a single `typeof x === 'string'` check in the UI.
 */

export interface V2Tx {
  id: string
  /** ISO-8601. */
  date: string
  /** Signed. Negative = outflow. */
  amount: number
  payee: string
  memo: string | null
  categoryId: string | null
  categoryName: string | null
  categoryEmoji: string | null
  /** Null on legacy rows imported before accounts were tracked. */
  accountId: string | null
  accountName: string
  isTransfer: boolean
  needsReview: boolean
  isPending: boolean
  isScheduled: boolean
}

export interface V2Account {
  id: string
  name: string
  kind: string
  institution: string | null
  currency: string
  /** Cash balance. */
  balance: number
  /** Holdings market value (broker accounts); 0 otherwise. */
  marketValue: number
  /** Raw worth of the account: balance + marketValue. Always positive for loans. */
  total: number
  /**
   * Signed contribution to net worth — the number a screen may safely add up.
   *
   * A loan's `currentBalance` is NOT its liability: `getNetWorth` derives the
   * remaining debt from the amortization schedule, which on a real loan differs
   * from the stored balance by thousands. Summing `total` therefore produces a
   * headline that contradicts the dashboard. This field carries the
   * authoritative figure (negative for loans, 0 when excluded from net worth).
   */
  netContribution: number
  /** Amortization-derived remaining debt. Loans only. */
  debt: number | null
  /**
   * The loan contract, so a client holding its own ledger can walk the
   * schedule rather than freeze `debt` at the moment it copied it. Loans only;
   * null when the account is not one or the contract is not configured.
   */
  loanOriginalPrincipal: number | null
  loanInterestRate: number | null
  loanTermMonths: number | null
  loanMonthlyPayment: number | null
  isIncludedInNetWorth: boolean
  isArchived: boolean
  syncProvider: string
  lastSyncedAt: string | null
  displayColor: string | null
  displayIcon: string | null
  loan: {
    rate: number | null
    monthlyPayment: number | null
    termMonths: number | null
    startDate: string | null
  } | null
}

export interface V2Category {
  id: string
  name: string
  emoji: string | null
  groupName: string
  /** 'income' | 'expense' | 'adjustment' — see `mapCategories`. */
  groupKind: string
  /**
   * The loan account this category mirrors, when it mirrors one. Filing a
   * transaction here is what moves that loan's remaining debt.
   */
  linkedLoanAccountId: string | null
}

export interface V2Holding {
  id: string
  label: string
  quantity: number
  costBasis: number
  marketValue: number
  plusValue: number
  plusValuePct: number | null
  lastPrice: number | null
  isStale: boolean
}

/**
 * Server actions the v2 screens can call. Each app binds its own
 * implementations — identical signatures, different data layer.
 */
export interface V2Actions {
  addTransaction: (input: AddTransactionInput) => Promise<ActionResult<{ id: string }>>
  addTransfer: (input: AddTransferInput) => Promise<ActionResult<{ transferPairId: string }>>
  updateTransactionCategory: (
    transactionId: string,
    categoryId: string | null,
  ) => Promise<ActionResult>
  approveTransaction: (transactionId: string) => Promise<ActionResult>
  softDeleteTransaction: (transactionId: string) => Promise<ActionResult>
  syncAllBanks: () => Promise<
    ActionResult<{
      connectionsSynced: number
      inactiveConnections: number
      accountsSynced: number
      transactionsInserted: number
    }>
  >
  setCategoryAssigned: (input: SetCategoryAssignedInput) => Promise<ActionResult>
}

/** The subset the quick-add sheet needs — kept narrow so it is easy to stub. */
export type V2AddActions = Pick<V2Actions, 'addTransaction' | 'addTransfer' | 'syncAllBanks'>
