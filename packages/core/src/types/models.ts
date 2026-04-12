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
  accountId: string
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

// ============ Composite types ============

export interface CategoryGroupWithCategories extends CategoryGroup {
  categories: Category[]
}

export interface TransactionWithRelations extends Transaction {
  account: Account
  category: Category | null
}
