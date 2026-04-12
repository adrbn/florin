import type {
  Account,
  BankConnection,
  Category,
  CategoryGroupWithCategories,
  CategorizationRule,
  TransactionWithRelations,
} from './models.js'

// ============ Query result types ============

export interface NetWorth {
  gross: number
  liability: number
  net: number
}

export interface BurnOptions {
  fixedOnly?: boolean
}

export interface PatrimonyPoint {
  date: string
  balance: number
}

export interface CategoryBreakdownItem {
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
  getNetWorthSeries(months?: number): Promise<NetWorthPoint[]>
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
  deleteAccount(id: string): Promise<ActionResult>
  setAccountArchived(id: string, archived: boolean): Promise<ActionResult>
  reorderAccounts(orderedIds: string[]): Promise<ActionResult>
  mergeAccount(sourceId: string, targetId: string): Promise<ActionResult>
  updateLoanSettings(input: LoanSettingsInput): Promise<ActionResult>

  addTransaction(input: AddTransactionInput): Promise<ActionResult<{ id: string }>>
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
}
