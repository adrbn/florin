import type {
  Account,
  BankConnection,
  Category,
  CategoryGroupWithCategories,
  CategorizationRule,
  RecurringFrequency,
  RecurringKind,
  RecurringRule,
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

/**
 * Projected net worth = realized net + the sum of scheduled (planned) rows
 * within the horizon. `scheduledDelta` is the difference so the UI can render
 * "réalisé (+X prévu)" without recomputing.
 */
export interface ProjectedNetWorth {
  projected: number
  scheduledDelta: number
}

export interface PatrimonyPoint {
  date: string
  balance: number
  /** True for forward-looking (projected) points; absent/false for realized. */
  projected?: boolean
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

export type TopSpendMode = 'transactions' | 'merchants'

export interface TopSpendParams {
  /** Single transactions, or merchants aggregated by payee. */
  mode: TopSpendMode
  /** How many rows to return (5/10/20). */
  limit: number
  /** Lookback window in days. */
  days: number
  /** Category filter, or null for all. */
  categoryId: string | null
  /** Only count expenses whose absolute amount is ≥ this (0 = no minimum). */
  minAmount: number
}

export interface TopSpendItem {
  /** React key — the transaction id, or the merchant grouping key. */
  id: string
  /** Display name (payee for a transaction, cleaned merchant name otherwise). */
  label: string
  /** Absolute amount: a single charge, or the merchant's summed total. */
  amount: number
  /** Share of the period's total filtered expense, 0–100. */
  pctOfPeriod: number
  /** Transactions mode: the charge date (ISO). Merchants mode: null. */
  date: string | null
  /** Transactions mode: category name. Merchants mode: null. */
  categoryName: string | null
  /** Merchants mode: number of charges aggregated. Transactions mode: null. */
  count: number | null
}

export interface TopSpendResult {
  items: TopSpendItem[]
  /** Total filtered expense over the window — the denominator for `pctOfPeriod`. */
  periodTotal: number
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
 * Time-pivoted spending by category. `months` is a chronological list of
 * YYYY-MM keys (oldest → newest) covering the window. Each entry in
 * `categories` aligns its `monthly` array with `months` by index; values are
 * absolute expense totals (refunds subtracted via signed SUM before abs).
 * Categories are pre-sorted by total descending so consumers can slice
 * `.slice(0, N)` to pick the heaviest spenders.
 */
export interface CategorySpendingSeries {
  months: string[]
  categories: Array<{
    categoryId: string
    categoryName: string
    emoji: string | null
    monthly: number[]
    total: number
  }>
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
  /**
   * Fixed-category spend so far this month (rent, loan, insurance, subs).
   * Big lumpy bills shouldn't be extrapolated forward at a daily pace, so the
   * month forecast subtracts these before projecting. See computeMonthForecast.
   */
  monthSpentFixed: number
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
  /** True when the category is flagged fixed (rent, loan, insurance, subs). */
  isFixed: boolean
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

export interface ActionResult<T = unknown> {
  success: boolean
  error?: string
  data?: T
}

// ============ Holdings / portfolio (Phase 2) ============

/** A security position inside a broker_portfolio account, normalized for the UI. */
export interface HoldingView {
  id: string
  accountId: string
  label: string
  isin: string | null
  quoteSymbol: string | null
  quantity: number
  /** Total amount paid for the position (PRU × quantity), in `currency`. */
  costBasis: number
  currency: string
  lastPrice: number | null
  /** ISO string, normalized across both DBs. */
  lastPriceAt: string | null
  /** quantity × (lastPrice ?? 0). */
  marketValue: number
  /** marketValue − costBasis. */
  plusValue: number
  /** Percent gain/loss, or null when costBasis is 0. */
  plusValuePct: number | null
  /** lastPriceAt older than 48h. */
  isStale: boolean
}

/** Aggregate valuation for one broker_portfolio account. */
export interface PortfolioValuation {
  marketValue: number
  costBasis: number
  /** marketValue − costBasis (latent gain/loss). */
  plusValue: number
  /** Idle cash in the wrapper (accounts.currentBalance). */
  cash: number
  /** Sum of inbound (cleared) transfer legs into this account. */
  verse: number
  /** (marketValue + cash) − verse — the part attributable to the market. */
  marche: number
}

export interface PriceRefreshResult {
  fetched: number
  failed: number
  skipped: boolean
}

export interface AddHoldingInput {
  accountId: string
  label: string
  isin?: string | null
  quoteSymbol?: string | null
  quantity: number
  costBasis: number
  currency?: string
}

export type UpdateHoldingInput = Partial<Omit<AddHoldingInput, 'accountId'>>

/**
 * One-click "buy" inside a broker account: add `quantity` shares for `amount` €
 * to a holding (existing via `holdingId`, or a new one) AND deduct `amount` from
 * the account's cash in a single action — so the user never has to record a
 * separate cash-out transaction. Avoids double-counting (cash → shares).
 */
export interface BuyHoldingInput {
  accountId: string
  /** Existing holding to add to; omit to create a new holding (needs `label`). */
  holdingId?: string | null
  label?: string
  isin?: string | null
  quoteSymbol?: string | null
  /** Shares bought. */
  quantity: number
  /** € spent — added to cost basis and deducted from the account's cash. */
  amount: number
}

// ============ Allocation & goal (Phase 3) ============

/** Net-worth partitioned for the allocation donut. cash + invested = gross. */
export interface NetWorthAllocation {
  cash: number
  invested: number
  loans: number
}

/** Inputs for the goal projection, derived from investment accounts + DCA rules. */
export interface InvestmentSnapshot {
  /** Total value across investment accounts (marketValue + idle cash). */
  investedValue: number
  /** Sum of active monthly recurring transfers into investment accounts (the DCA). */
  monthlyContribution: number
}

export interface GoalProjection {
  target: number
  currentValue: number
  monthlyContribution: number
  annualReturnPct: number
  /** Months until the target is reached, or null if unreachable in the horizon. */
  monthsToReach: number | null
  /** ISO date (YYYY-MM-DD) the target is reached, or null. */
  reachDateIso: string | null
  /** currentValue + contributions paid in by the reach date ("ce que tu as versé"). */
  contributed: number
  /** target − contributed ("ce que le marché a fait"). */
  marketGrowth: number
}

// ============ FlorinQueries interface ============

export interface FlorinQueries {
  getNetWorth(): Promise<NetWorth>
  /** Realized net worth plus scheduled rows within `horizonDays` (default 90). */
  getProjectedNetWorth(horizonDays?: number): Promise<ProjectedNetWorth>
  /** Map of accountId → sum of its scheduled (not-yet-realized) amounts. */
  getScheduledDeltaByAccount(): Promise<Record<string, number>>
  getMonthBurn(opts?: BurnOptions): Promise<number>
  getAvgMonthlyBurn(months?: number): Promise<number>
  getPatrimonyTimeSeries(months?: number): Promise<PatrimonyPoint[]>
  getMonthByCategory(): Promise<CategoryBreakdownItem[]>
  getTopExpenses(
    n?: number,
    days?: number,
    categoryId?: string | null,
  ): Promise<TopExpense[]>
  getTopSpend(params: TopSpendParams): Promise<TopSpendResult>
  countUncategorizedExpensesThisMonth(): Promise<number>
  getDataSourceInfo(): Promise<DataSourceInfo>
  getMonthlyFlows(months?: number): Promise<MonthlyFlow[]>
  getCategoryBreakdown(days?: number): Promise<CategoryShare[]>
  getAgeOfMoney(days?: number): Promise<number | null>
  getAgeOfMoneyHistory(months?: number): Promise<{ month: string; age: number | null }[]>
  getNetWorthSeries(months?: number): Promise<NetWorthPoint[]>
  getCategorySpendingSeries(months?: number): Promise<CategorySpendingSeries>
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
  listRecurringRules(): Promise<RecurringRule[]>
  listHoldings(accountId: string): Promise<HoldingView[]>
  getPortfolioValuation(accountId: string): Promise<PortfolioValuation>
  getNetWorthAllocation(): Promise<NetWorthAllocation>
  getInvestmentSnapshot(): Promise<InvestmentSnapshot>
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

/**
 * Recurrence options the add/transfer form can attach. When present, the
 * action spawns a {@link RecurringRule} (in addition to creating the one-off
 * the user just entered) and materializes its upcoming scheduled occurrences.
 */
export interface TransactionRecurringInput {
  frequency: RecurringFrequency
  /** Day of month 1–31 for the rule's occurrences. */
  dayOfMonth: number
  endDate?: Date | null
}

export interface AddTransactionInput {
  accountId: string
  occurredAt: Date
  amount: number
  payee: string
  memo?: string | null
  categoryId?: string | null
  recurring?: TransactionRecurringInput | null
}

export interface AddTransferInput {
  fromAccountId: string
  toAccountId: string
  /** Positive amount moved from → to. */
  amount: number
  occurredAt: Date
  memo?: string | null
  recurring?: TransactionRecurringInput | null
}

/**
 * Manual correction of an existing transaction's date / amount / payee / memo.
 * Every field is optional — only the provided ones change. Editing the date
 * re-derives status (future → 'scheduled', past → 'cleared') and the account
 * balance is recomputed so realized totals stay correct. Primary use: moving a
 * later reimbursement onto the day of the shared expense so a single day isn't
 * over-counted.
 */
export interface UpdateTransactionInput {
  occurredAt?: Date
  amount?: number
  payee?: string
  memo?: string | null
}

export interface CreateRecurringRuleInput {
  name: string
  kind: RecurringKind
  accountId: string
  toAccountId?: string | null
  /** Positive magnitude. */
  amount: number
  payee?: string
  categoryId?: string | null
  currency?: string
  memo?: string | null
  frequency: RecurringFrequency
  interval?: number
  dayOfMonth: number
  startDate: Date
  endDate?: Date | null
}

export interface UpdateRecurringRuleInput extends Partial<CreateRecurringRuleInput> {
  id: string
  isActive?: boolean
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
  /**
   * Edit an existing transaction's date / amount / payee / memo. Re-derives
   * status from the new date and recomputes the account balance.
   */
  updateTransaction(
    transactionId: string,
    input: UpdateTransactionInput,
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
  /**
   * Copy every monthly_budgets row from the prior month into (year, month).
   * Existing rows on the target month are preserved (ON CONFLICT DO NOTHING) —
   * only categories without a budget yet get filled in. Returns the number of
   * rows actually inserted.
   */
  copyPreviousMonthBudgets(
    year: number,
    month: number,
  ): Promise<ActionResult<{ copied: number; sourceYear: number; sourceMonth: number }>>

  // ---------- recurring rules ----------
  createRecurringRule(input: CreateRecurringRuleInput): Promise<ActionResult<{ id: string }>>
  updateRecurringRule(input: UpdateRecurringRuleInput): Promise<ActionResult>
  deleteRecurringRule(
    id: string,
    opts?: { deleteGeneratedScheduled?: boolean },
  ): Promise<ActionResult>
  /**
   * Materialize scheduled occurrences for every active rule up to the horizon.
   * Idempotent (safe to call repeatedly — e.g. on each dashboard load / sync).
   */
  materializeScheduledTransactions(): Promise<ActionResult<{ generated: number }>>

  // ---------- reconciliation ----------
  /**
   * Accept a merge suggestion: copy the bank row's externalId/rawData onto the
   * candidate, mark it cleared, then remove the duplicate bank row.
   */
  mergeBankTransaction(bankTxId: string, candidateTxId: string): Promise<ActionResult>
  /** Dismiss a merge suggestion — keep both rows, just clear the link. */
  dismissMergeSuggestion(bankTxId: string): Promise<ActionResult>

  // ---------- holdings / portfolio (Phase 2) ----------
  addHolding(input: AddHoldingInput): Promise<ActionResult<{ id: string }>>
  updateHolding(id: string, input: UpdateHoldingInput): Promise<ActionResult>
  deleteHolding(id: string): Promise<ActionResult>
  /** One-click buy: add shares to a holding + deduct the cost from account cash. */
  buyHolding(input: BuyHoldingInput): Promise<ActionResult<{ holdingId: string }>>
  // NB: price refresh lives at the app level (needs app-specific pricing config);
  // it is bound to the HoldingsCard onRefreshPrices prop per app.
}
