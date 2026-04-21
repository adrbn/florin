import type {
  Account,
  BankConnection,
  Category,
  CategoryGroupWithCategories,
  CategorizationRule,
  TransactionWithRelations,
} from './models'

// ============ Query result types ============

export interface NetWorth {
  gross: number
  liability: number
  net: number
  /**
   * Net worth estimated as of the same day of the previous month. Derived by
   * walking transactions backward from `net` on non-loan accounts that are
   * included in net worth. Null when the history is too short to make the
   * comparison meaningful (e.g. brand-new install).
   */
  netMonthAgo: number | null
}

export interface BurnOptions {
  fixedOnly?: boolean
}

export interface PatrimonyPoint {
  date: string
  balance: number
}

export interface CategoryBreakdownItem {
  categoryId: string
  groupName: string
  categoryName: string
  emoji: string | null
  total: number
  color: string | null
}

export interface TopExpense {
  id: string
  payee: string
  date: Date
  amount: number
  categoryName: string | null
}

export interface DataSourceInfo {
  kind: 'legacy_xlsx' | 'manual' | 'mixed' | 'empty'
  lastImportAt: Date | null
  hasBankApi: boolean
  totalAccounts: number
  legacyAccounts: number
  manualAccounts: number
}

export interface MonthlyFlow {
  month: string
  income: number
  expense: number
  net: number
}

export interface CategoryShare {
  groupName: string
  categoryName: string
  emoji: string | null
  total: number
}

export interface NetWorthPoint {
  month: string
  cumulative: number
}

/**
 * "Left to spend this month" — derived from the salary tx category. We find
 * the category of the most recent large positive transaction (a user's
 * paycheck), then use the sum of income in that category this month as the
 * ceiling, minus this month's burn.
 */
export interface LeftToSpend {
  salaryCategoryId: string | null
  salaryCategoryName: string | null
  monthIncome: number
  monthSpent: number
  leftToSpend: number
  /** Average daily spend so far this month (monthSpent / daysElapsed). */
  dailyAvgSpent: number
  /** leftToSpend / daysRemaining. Null when no salary detected or month is over. */
  dailyBudgetRemaining: number | null
  daysElapsed: number
  daysRemaining: number
}

/** Per-day spend used by the Reflect heatmap. Amount is abs(negative sum). */
export interface DailySpend {
  date: string
  amount: number
}

export interface DailyCategorySpend {
  date: string
  categoryId: string | null
  categoryName: string | null
  groupName: string | null
  amount: number
}

/** Rolling savings rate (percentage, -100 to +100) across windows. */
export interface SavingsRates {
  threeMonth: number | null
  sixMonth: number | null
  twelveMonth: number | null
}

/** One detected subscription — a recurring payee+amount pattern. */
export interface SubscriptionMatch {
  payee: string
  amount: number
  cadenceDays: number
  samples: number
  lastSeen: string
  annualCost: number
  categoryName: string | null
}

// ============ Plan tab ============

export interface PlanCategory {
  /** categories.id */
  id: string
  name: string
  emoji: string | null
  /** monthly_budgets.assigned for this (year, month, category). 0 if no row. */
  assigned: number
  /** Sum of -signed(amount) for non-transfer, non-deleted transactions in this
   * category's month. Outflows add, refunds subtract (YNAB Activity semantics). */
  spent: number
  /** assigned - spent. Negative = overspent. */
  available: number
  /** monthly_budgets.note. null if no row. */
  note: string | null
}

export interface PlanGroup {
  /** category_groups.id */
  id: string
  name: string
  kind: 'income' | 'expense'
  color: string | null
  categories: PlanCategory[]
  /** Sum of child .assigned. */
  assigned: number
  /** Sum of child .spent. */
  spent: number
  /** Sum of child .available. */
  available: number
  /** Count of child categories with available < 0. */
  overspentCount: number
}

export interface MonthPlan {
  year: number
  month: number
  /** Only expense groups appear here — income groups feed `income` below. */
  groups: PlanGroup[]
  /** Sum of all transactions in income-kind categories this month, transfers/soft-deletes excluded. */
  income: number
  /** Sum of .assigned across every PlanCategory. */
  totalAssigned: number
  /** income - totalAssigned. Negative = "Assigned Too Much". */
  readyToAssign: number
  /** Total count of overspent categories across all expense groups. */
  overspentCount: number
}

/** Minimal transaction row shown inside the Plan-category detail modal. */
export interface PlanCategoryTransaction {
  id: string
  /** ISO-8601 date string (UTC). */
  occurredAt: string
  payee: string
  memo: string | null
  /** Signed amount. Negative = outflow, positive = refund/inflow. */
  amount: number
  currency: string
}

export type ListPlanCategoryTransactions = (
  categoryId: string,
  year: number,
  month: number,
) => Promise<PlanCategoryTransaction[]>

export interface SetCategoryAssignedInput {
  year: number
  month: number
  categoryId: string
  amount: number
  note?: string | null
}

export type TransactionDirection = 'all' | 'expense' | 'income'

export interface ListTransactionsOptions {
  limit?: number
  offset?: number
  accountId?: string
  needsReviewOnly?: boolean
  startDate?: string
  endDate?: string
  direction?: TransactionDirection
  excludeTransfers?: boolean
  payeeSearch?: string
  categoryId?: string
  minAmount?: number
  maxAmount?: number
}

export interface PaginatedResult<T> {
  rows: T[]
  total: number
}

export interface ActionResult<T = void> {
  success: boolean
  error?: string
  data?: T
}

// ============ FlorinQueries interface ============

export interface FlorinQueries {
  getNetWorth(): Promise<NetWorth>
  getMonthBurn(opts?: BurnOptions): Promise<number>
  getAvgMonthlyBurn(months?: number): Promise<number>
  getPatrimonyTimeSeries(months?: number): Promise<PatrimonyPoint[]>
  getMonthByCategory(): Promise<CategoryBreakdownItem[]>
  getTopExpenses(
    n?: number,
    days?: number,
    categoryId?: string | null,
  ): Promise<TopExpense[]>
  countUncategorizedExpensesThisMonth(): Promise<number>
  getDataSourceInfo(): Promise<DataSourceInfo>
  getMonthlyFlows(months?: number): Promise<MonthlyFlow[]>
  getCategoryBreakdown(days?: number): Promise<CategoryShare[]>
  getAgeOfMoney(days?: number): Promise<number | null>
  getAgeOfMoneyHistory(months?: number): Promise<{ month: string; age: number | null }[]>
  getNetWorthSeries(months?: number): Promise<NetWorthPoint[]>
  getLeftToSpendThisMonth(): Promise<LeftToSpend>
  getDailySpend(days?: number): Promise<DailySpend[]>
  getDailySpendByCategory(days?: number): Promise<DailyCategorySpend[]>
  getSavingsRates(): Promise<SavingsRates>
  getSubscriptions(): Promise<SubscriptionMatch[]>
  listTransactions(options?: ListTransactionsOptions): Promise<TransactionWithRelations[]>
  countTransactions(options?: ListTransactionsOptions): Promise<number>
  countNeedsReview(): Promise<number>
  listAccounts(options?: { includeArchived?: boolean }): Promise<Account[]>
  getAccountById(
    id: string,
  ): Promise<(Account & { bankConnection?: BankConnection | null }) | null>
  listBankConnections(): Promise<BankConnection[]>
  listCategoriesByGroup(): Promise<CategoryGroupWithCategories[]>
  listCategoriesFlat(): Promise<
    Array<{
      id: string
      name: string
      emoji: string | null
      groupName: string
      linkedLoanAccountId: string | null
    }>
  >
  listCategorizationRules(): Promise<CategorizationRule[]>
  getMonthPlan(year: number, month: number): Promise<MonthPlan>
}

// ============ Action input types ============

export interface CreateAccountInput {
  name: string
  kind: string
  institution?: string | null
  currentBalance: number
  displayIcon?: string | null
  displayColor?: string | null
}

export interface UpdateAccountInput extends CreateAccountInput {
  id: string
  isIncludedInNetWorth?: boolean
}

export interface AddTransactionInput {
  accountId: string
  occurredAt: Date
  amount: number
  payee: string
  memo?: string | null
  categoryId?: string | null
}

export interface AddTransferInput {
  fromAccountId: string
  toAccountId: string
  /** Positive amount moved from → to. */
  amount: number
  occurredAt: Date
  memo?: string | null
}

export interface CreateCategoryInput {
  groupId: string
  name: string
  emoji?: string | null
  isFixed?: boolean
}

export interface UpdateCategoryInput {
  id: string
  name: string
  emoji?: string | null
  isFixed?: boolean
}

export interface CreateGroupInput {
  name: string
  kind: 'income' | 'expense'
  color?: string | null
}

export interface LoanSettingsInput {
  id: string
  loanOriginalPrincipal: number | null
  loanInterestRatePercent: number | null
  loanStartDate: string | null
  loanTermMonths: number | null
  loanMonthlyPayment: number | null
}

// ============ FlorinMutations interface ============

export interface FlorinMutations {
  createAccount(input: CreateAccountInput): Promise<ActionResult<{ id: string }>>
  updateAccount(input: UpdateAccountInput): Promise<ActionResult>
  deleteAccount(id: string, opts?: { deleteTransactions?: boolean }): Promise<ActionResult>
  setAccountArchived(id: string, archived: boolean): Promise<ActionResult>
  reorderAccounts(orderedIds: string[]): Promise<ActionResult>
  mergeAccount(sourceId: string, targetId: string): Promise<ActionResult>
  updateLoanSettings(input: LoanSettingsInput): Promise<ActionResult>

  addTransaction(input: AddTransactionInput): Promise<ActionResult<{ id: string }>>
  addTransfer(
    input: AddTransferInput,
  ): Promise<ActionResult<{ transferPairId: string }>>
  /**
   * Convert an existing transaction (usually review-pending) into one leg of an
   * internal transfer. If a matching counterpart already exists on
   * `counterpartAccountId` (opposite sign, same |amount|, within ±5 days), both
   * rows are linked; otherwise a synthetic counterpart leg is inserted so the
   * books stay balanced.
   */
  linkAsInternalTransfer(
    transactionId: string,
    counterpartAccountId: string,
  ): Promise<ActionResult<{ transferPairId: string; mode: 'paired' | 'created' }>>
  updateTransactionCategory(
    transactionId: string,
    categoryId: string | null,
  ): Promise<ActionResult>
  softDeleteTransaction(id: string): Promise<ActionResult>
  approveTransaction(transactionId: string): Promise<ActionResult>
  approveAllTransactions(): Promise<ActionResult<{ approved: number }>>
  bulkUpdateTransactionCategory(
    ids: string[],
    categoryId: string | null,
  ): Promise<ActionResult<{ updated: number }>>
  bulkApproveTransactions(ids: string[]): Promise<ActionResult<{ approved: number }>>
  bulkSoftDeleteTransactions(ids: string[]): Promise<ActionResult<{ deleted: number }>>

  createCategory(input: CreateCategoryInput): Promise<ActionResult<{ id: string }>>
  updateCategory(input: UpdateCategoryInput): Promise<ActionResult>
  deleteCategory(id: string): Promise<ActionResult>

  createCategoryGroup(input: CreateGroupInput): Promise<ActionResult<{ id: string }>>
  updateCategoryGroup(input: CreateGroupInput & { id: string }): Promise<ActionResult>
  deleteCategoryGroup(id: string): Promise<ActionResult>

  setCategoryLoanLink(
    categoryId: string,
    loanAccountId: string | null,
  ): Promise<ActionResult<{ touched: number }>>

  setCategoryAssigned(input: SetCategoryAssignedInput): Promise<ActionResult>
  clearCategoryAssigned(
    year: number,
    month: number,
    categoryId: string,
  ): Promise<ActionResult>
}
