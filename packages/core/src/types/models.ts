// ============ Type unions ============

export type AccountKind =
  | 'checking'
  | 'savings'
  | 'cash'
  | 'loan'
  | 'broker_cash'
  | 'broker_portfolio'
  | 'other'

export type SyncProvider = 'enable_banking' | 'pytr' | 'manual' | 'legacy'

export type CategoryKind = 'income' | 'expense'

export type TransactionSource =
  | 'enable_banking'
  | 'pytr'
  | 'manual'
  | 'legacy_xlsx'
  | 'ios_shortcut'

/**
 * Lifecycle status of a transaction.
 * - `cleared`: real money. Counts toward the realized account balance and net
 *   worth (when also dated <= today).
 * - `scheduled`: a planned / forecast row (e.g. a future DCA contribution). It
 *   shows in the ledger as "Prévu" and feeds projections, but never affects the
 *   realized balance until it is cleared (via reconciliation or manually).
 */
export type TransactionStatus = 'cleared' | 'scheduled'

/** Cadence of a recurring rule. Phase 1 only materializes 'monthly'. */
export type RecurringFrequency = 'monthly'

/** A recurring rule either generates a single transaction or a transfer pair. */
export type RecurringKind = 'transfer' | 'transaction'

// ============ Model interfaces ============

export interface Account {
  id: string
  name: string
  kind: AccountKind
  institution: string | null
  currency: string
  iban: string | null
  isActive: boolean
  isArchived: boolean
  isIncludedInNetWorth: boolean
  currentBalance: string
  lastSyncedAt: Date | null
  syncProvider: SyncProvider
  syncExternalId: string | null
  bankConnectionId: string | null
  displayColor: string | null
  displayIcon: string | null
  displayOrder: number
  loanOriginalPrincipal: string | null
  loanInterestRate: string | null
  loanStartDate: Date | null
  loanTermMonths: number | null
  loanMonthlyPayment: string | null
  createdAt: Date
  updatedAt: Date
}

export interface BankConnection {
  id: string
  provider: string
  sessionId: string
  aspspName: string
  aspspCountry: string
  status: string
  validUntil: Date
  syncStartDate: Date
  lastSyncedAt: Date | null
  lastSyncError: string | null
  createdAt: Date
  updatedAt: Date
}

export interface CategoryGroup {
  id: string
  name: string
  kind: CategoryKind
  displayOrder: number
  color: string | null
  createdAt: Date
}

export interface Category {
  id: string
  groupId: string
  name: string
  emoji: string | null
  displayOrder: number
  isFixed: boolean
  isArchived: boolean
  linkedLoanAccountId: string | null
  createdAt: Date
}

export interface Transaction {
  id: string
  accountId: string | null
  occurredAt: Date
  recordedAt: Date
  amount: string
  currency: string
  payee: string
  normalizedPayee: string
  memo: string | null
  categoryId: string | null
  source: TransactionSource
  externalId: string | null
  legacyId: string | null
  isPending: boolean
  needsReview: boolean
  transferPairId: string | null
  /** Lifecycle status — see {@link TransactionStatus}. */
  status: TransactionStatus
  /** Set on rows materialized from a recurring rule; links back to it. */
  recurringRuleId: string | null
  /**
   * On a freshly-imported bank row that fuzzily matches an existing
   * scheduled/manual row, this points at that candidate so the Review queue
   * can offer a merge. Null otherwise (and on the candidate itself).
   */
  mergeSuggestedTxId: string | null
  rawData: string | null
  deletedAt: Date | null
  createdAt: Date
  updatedAt: Date
}

export interface CategorizationRule {
  id: string
  priority: number
  categoryId: string
  matchPayeeRegex: string | null
  matchMinAmount: string | null
  matchMaxAmount: string | null
  matchAccountId: string | null
  isActive: boolean
  hitsCount: number
  lastHitAt: Date | null
  note: string | null
  createdAt: Date
  updatedAt: Date
}

export interface BalanceSnapshot {
  id: string
  snapshotDate: Date
  accountId: string | null
  balance: string
  createdAt: Date
}

/**
 * A user-defined recurring rule that materializes `scheduled` transactions
 * ahead of time (e.g. a monthly DCA: 500 € transfer CCP → PEA on the 2nd).
 * Money convention follows {@link Account}: amount is a decimal string; dates
 * are `Date`. Generated occurrences carry the rule id in
 * `Transaction.recurringRuleId`.
 */
export interface RecurringRule {
  id: string
  name: string
  kind: RecurringKind
  /** Source ("from") account. */
  accountId: string
  /** Destination account for transfers; null for single-transaction rules. */
  toAccountId: string | null
  /** Positive magnitude moved each occurrence. */
  amount: string
  payee: string
  categoryId: string | null
  currency: string
  memo: string | null
  frequency: RecurringFrequency
  /** Every N periods (1 = every month). */
  interval: number
  /** Day of month 1–31; clamped to the month length when materializing. */
  dayOfMonth: number
  startDate: Date
  endDate: Date | null
  isActive: boolean
  /** Last occurrence date already materialized; null before first run. */
  lastMaterializedDate: Date | null
  createdAt: Date
  updatedAt: Date
}

// ============ Composite types ============

export interface CategoryGroupWithCategories extends CategoryGroup {
  categories: Category[]
}

export interface TransactionWithRelations extends Transaction {
  account: Account | null
  category: Category | null
}
