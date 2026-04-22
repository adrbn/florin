import { relations, sql } from 'drizzle-orm'
import {
  boolean,
  index,
  integer,
  numeric,
  pgEnum,
  pgTable,
  text,
  timestamp,
  uniqueIndex,
  uuid,
} from 'drizzle-orm/pg-core'

// ============ ENUMS ============
export const accountKindEnum = pgEnum('account_kind', [
  'checking',
  'savings',
  'cash',
  'loan',
  'broker_cash',
  'broker_portfolio',
  'other',
])

export const syncProviderEnum = pgEnum('sync_provider', [
  'enable_banking',
  'pytr',
  'manual',
  'legacy',
])

export const categoryKindEnum = pgEnum('category_kind', ['income', 'expense'])

export const transactionSourceEnum = pgEnum('transaction_source', [
  'enable_banking',
  'pytr',
  'manual',
  'legacy_xlsx',
  'ios_shortcut',
])

// ============ users ============
export const users = pgTable('users', {
  id: uuid('id').primaryKey().defaultRandom(),
  email: text('email').notNull().unique(),
  passwordHash: text('password_hash').notNull(),
  locale: text('locale').notNull().default('fr-FR'),
  baseCurrency: text('base_currency').notNull().default('EUR'),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
})

// ============ bank_connections ============
// One row per Enable Banking consent session. A single session links one or
// more accounts at one ASPSP (bank). PSD2 caps consent at ~90 days so each
// session has a `validUntil` — the UI surfaces "needs re-auth" once expired.
export const bankConnections = pgTable('bank_connections', {
  id: uuid('id').primaryKey().defaultRandom(),
  provider: text('provider').notNull().default('enable_banking'),
  /** Enable Banking session UUID (returned by POST /sessions). */
  sessionId: text('session_id').notNull().unique(),
  /** ASPSP (bank) identifier as Enable Banking returns it, e.g. "La Banque Postale". */
  aspspName: text('aspsp_name').notNull(),
  /** ISO country of the ASPSP, e.g. "FR". */
  aspspCountry: text('aspsp_country').notNull(),
  /** 'active' while consent is valid, 'expired' past validUntil, 'revoked' if user revoked. */
  status: text('status').notNull().default('active'),
  /** When the consent expires — PSD2 caps at ~90–180 days depending on bank. */
  validUntil: timestamp('valid_until', { withTimezone: true }).notNull(),
  /**
   * Lower bound for transaction sync. Never fetch transactions dated before
   * this. Defaults to the connection creation date so the first sync doesn't
   * pull history that might overlap with legacy XLSX imports. User can move
   * this earlier (down to 90 days ago) or later as needed.
   */
  syncStartDate: timestamp('sync_start_date', { withTimezone: false, mode: 'date' })
    .notNull()
    .defaultNow(),
  /** Last successful sync across all accounts in this connection. */
  lastSyncedAt: timestamp('last_synced_at', { withTimezone: true }),
  /** Human-readable error from the last failed sync (for display in /accounts). */
  lastSyncError: text('last_sync_error'),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
})

// ============ accounts ============
export const accounts = pgTable('accounts', {
  id: uuid('id').primaryKey().defaultRandom(),
  name: text('name').notNull(),
  kind: accountKindEnum('kind').notNull(),
  institution: text('institution'),
  currency: text('currency').notNull().default('EUR'),
  iban: text('iban'),
  isActive: boolean('is_active').notNull().default(true),
  isArchived: boolean('is_archived').notNull().default(false),
  isIncludedInNetWorth: boolean('is_included_in_net_worth').notNull().default(true),
  currentBalance: numeric('current_balance', { precision: 14, scale: 2 }).notNull().default('0'),
  /**
   * Anchor value used to reconstruct currentBalance. For local-ledger accounts
   * (manual, legacy), we maintain the invariant:
   *   currentBalance = openingBalance + SUM(non-deleted transactions)
   * For bank-synced accounts (enable_banking, pytr), currentBalance is
   * overwritten from the sync API and openingBalance is unused.
   */
  openingBalance: numeric('opening_balance', { precision: 14, scale: 2 }).notNull().default('0'),
  lastSyncedAt: timestamp('last_synced_at', { withTimezone: true }),
  syncProvider: syncProviderEnum('sync_provider').notNull().default('manual'),
  syncExternalId: text('sync_external_id'),
  /** FK to bank_connections when syncProvider = 'enable_banking'. Null for manual/legacy. */
  bankConnectionId: uuid('bank_connection_id').references(() => bankConnections.id, {
    onDelete: 'set null',
  }),
  displayColor: text('display_color'),
  displayIcon: text('display_icon'),
  displayOrder: integer('display_order').notNull().default(0),
  // Loan-specific fields. All nullable because only kind='loan' accounts
  // use them, and the user might not have all the details upfront. The
  // UI enforces "need all four to compute a schedule" separately.
  //   loanOriginalPrincipal → the amount originally borrowed (encours initial)
  //   loanInterestRate      → annual rate as a decimal (e.g. 0.0350 for 3.50%)
  //   loanStartDate         → first payment date, anchors the amortization
  //   loanTermMonths        → total number of monthly instalments
  //   loanMonthlyPayment    → fixed mensualité, in the account currency
  loanOriginalPrincipal: numeric('loan_original_principal', {
    precision: 14,
    scale: 2,
  }),
  loanInterestRate: numeric('loan_interest_rate', { precision: 7, scale: 6 }),
  loanStartDate: timestamp('loan_start_date', { withTimezone: false, mode: 'date' }),
  loanTermMonths: integer('loan_term_months'),
  loanMonthlyPayment: numeric('loan_monthly_payment', { precision: 14, scale: 2 }),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
})

// ============ category_groups ============
export const categoryGroups = pgTable('category_groups', {
  id: uuid('id').primaryKey().defaultRandom(),
  name: text('name').notNull().unique(),
  kind: categoryKindEnum('kind').notNull(),
  displayOrder: integer('display_order').notNull().default(0),
  color: text('color'),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
})

// ============ categories ============
export const categories = pgTable(
  'categories',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    groupId: uuid('group_id')
      .notNull()
      .references(() => categoryGroups.id, { onDelete: 'cascade' }),
    name: text('name').notNull(),
    emoji: text('emoji'),
    displayOrder: integer('display_order').notNull().default(0),
    isFixed: boolean('is_fixed').notNull().default(false),
    isArchived: boolean('is_archived').notNull().default(false),
    /**
     * Optional link to a loan account. When a transaction is categorized
     * into a category that has this set, the loan account's currentBalance
     * gets reduced by |amount| automatically — this is how "pay my student
     * loan" on a checking account ripples into the loan balance, YNAB-style.
     * Null for normal expense/income categories.
     */
    linkedLoanAccountId: uuid('linked_loan_account_id').references(() => accounts.id, {
      onDelete: 'set null',
    }),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [uniqueIndex('categories_group_name_unique').on(t.groupId, t.name)],
)

// ============ transactions ============
export const transactions = pgTable(
  'transactions',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    accountId: uuid('account_id').references(() => accounts.id, { onDelete: 'set null' }),
    occurredAt: timestamp('occurred_at', { withTimezone: false, mode: 'date' }).notNull(),
    recordedAt: timestamp('recorded_at', { withTimezone: true }).notNull().defaultNow(),
    amount: numeric('amount', { precision: 14, scale: 2 }).notNull(),
    currency: text('currency').notNull().default('EUR'),
    payee: text('payee').notNull().default(''),
    normalizedPayee: text('normalized_payee').notNull().default(''),
    memo: text('memo'),
    categoryId: uuid('category_id').references(() => categories.id, { onDelete: 'set null' }),
    source: transactionSourceEnum('source').notNull(),
    externalId: text('external_id'),
    legacyId: text('legacy_id'),
    isPending: boolean('is_pending').notNull().default(false),
    /**
     * YNAB-style review flag. Set to true when a transaction is auto-imported
     * from a bank API so the user has a chance to confirm the payee/category
     * before it counts as "approved". Manual entries land already approved.
     */
    needsReview: boolean('needs_review').notNull().default(false),
    transferPairId: uuid('transfer_pair_id'),
    rawData: text('raw_data'),
    deletedAt: timestamp('deleted_at', { withTimezone: true }),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [
    index('transactions_account_date_idx').on(t.accountId, t.occurredAt),
    index('transactions_category_date_idx').on(t.categoryId, t.occurredAt),
    uniqueIndex('transactions_source_external_unique')
      .on(t.source, t.externalId)
      .where(sql`${t.externalId} IS NOT NULL`),
    uniqueIndex('transactions_legacy_unique').on(t.legacyId).where(sql`${t.legacyId} IS NOT NULL`),
    index('transactions_not_deleted_idx').on(t.occurredAt).where(sql`${t.deletedAt} IS NULL`),
    index('transactions_needs_review_idx').on(t.needsReview).where(sql`${t.needsReview} = true`),
  ],
)

// ============ balance_snapshots ============
export const balanceSnapshots = pgTable(
  'balance_snapshots',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    snapshotDate: timestamp('snapshot_date', { withTimezone: false, mode: 'date' }).notNull(),
    accountId: uuid('account_id').references(() => accounts.id, { onDelete: 'cascade' }),
    balance: numeric('balance', { precision: 14, scale: 2 }).notNull(),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [uniqueIndex('balance_snapshots_date_account_unique').on(t.snapshotDate, t.accountId)],
)

// ============ categorization_rules ============
export const categorizationRules = pgTable('categorization_rules', {
  id: uuid('id').primaryKey().defaultRandom(),
  priority: integer('priority').notNull().default(0),
  categoryId: uuid('category_id')
    .notNull()
    .references(() => categories.id, { onDelete: 'cascade' }),
  matchPayeeRegex: text('match_payee_regex'),
  matchMinAmount: numeric('match_min_amount', { precision: 14, scale: 2 }),
  matchMaxAmount: numeric('match_max_amount', { precision: 14, scale: 2 }),
  matchAccountId: uuid('match_account_id').references(() => accounts.id, { onDelete: 'cascade' }),
  isActive: boolean('is_active').notNull().default(true),
  hitsCount: integer('hits_count').notNull().default(0),
  lastHitAt: timestamp('last_hit_at', { withTimezone: true }),
  note: text('note'),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
})

// ============ monthly_budgets ============
export const monthlyBudgets = pgTable(
  'monthly_budgets',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    year: integer('year').notNull(),
    month: integer('month').notNull(),
    categoryId: uuid('category_id')
      .notNull()
      .references(() => categories.id, { onDelete: 'cascade' }),
    assigned: numeric('assigned', { precision: 12, scale: 2 }).notNull().default('0'),
    note: text('note'),
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
    updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [
    uniqueIndex('monthly_budgets_ymc_unique').on(t.year, t.month, t.categoryId),
    index('monthly_budgets_ym_idx').on(t.year, t.month),
  ],
)

// ============ bank_sync_runs ============
/**
 * One row per invocation of syncConnection(). Lets the UI show a history of
 * sync attempts with per-account detail. See db-sqlite/src/schema.ts for the
 * full rationale — this table mirrors it for the PostgreSQL deployment.
 */
export const bankSyncRuns = pgTable(
  'bank_sync_runs',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    connectionId: uuid('connection_id')
      .notNull()
      .references(() => bankConnections.id, { onDelete: 'cascade' }),
    trigger: text('trigger').notNull().default('manual'),
    startedAt: timestamp('started_at', { withTimezone: true }).notNull().defaultNow(),
    finishedAt: timestamp('finished_at', { withTimezone: true }),
    status: text('status').notNull().default('running'),
    accountsTotal: integer('accounts_total').notNull().default(0),
    accountsOk: integer('accounts_ok').notNull().default(0),
    txInserted: integer('tx_inserted').notNull().default(0),
    errorSummary: text('error_summary'),
    durationMs: integer('duration_ms'),
  },
  (t) => [
    index('bank_sync_runs_connection_idx').on(t.connectionId, t.startedAt),
    index('bank_sync_runs_started_idx').on(t.startedAt),
  ],
)

// ============ bank_sync_account_results ============
export const bankSyncAccountResults = pgTable(
  'bank_sync_account_results',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    runId: uuid('run_id')
      .notNull()
      .references(() => bankSyncRuns.id, { onDelete: 'cascade' }),
    accountUid: text('account_uid').notNull(),
    accountId: uuid('account_id').references(() => accounts.id, { onDelete: 'set null' }),
    balanceFetched: boolean('balance_fetched').notNull().default(false),
    balanceError: text('balance_error'),
    detailsError: text('details_error'),
    txFetched: integer('tx_fetched').notNull().default(0),
    txInserted: integer('tx_inserted').notNull().default(0),
    txError: text('tx_error'),
  },
  (t) => [index('bank_sync_account_results_run_idx').on(t.runId)],
)

// Export inferred types
export type User = typeof users.$inferSelect
export type NewUser = typeof users.$inferInsert
export type Account = typeof accounts.$inferSelect
export type NewAccount = typeof accounts.$inferInsert
export type BankConnection = typeof bankConnections.$inferSelect
export type NewBankConnection = typeof bankConnections.$inferInsert
export type CategoryGroup = typeof categoryGroups.$inferSelect
export type Category = typeof categories.$inferSelect
export type Transaction = typeof transactions.$inferSelect
export type NewTransaction = typeof transactions.$inferInsert
export type BalanceSnapshot = typeof balanceSnapshots.$inferSelect
export type CategorizationRule = typeof categorizationRules.$inferSelect
export type NewCategorizationRule = typeof categorizationRules.$inferInsert
export type MonthlyBudget = typeof monthlyBudgets.$inferSelect
export type NewMonthlyBudget = typeof monthlyBudgets.$inferInsert
export type BankSyncRun = typeof bankSyncRuns.$inferSelect
export type NewBankSyncRun = typeof bankSyncRuns.$inferInsert
export type BankSyncAccountResult = typeof bankSyncAccountResults.$inferSelect
export type NewBankSyncAccountResult = typeof bankSyncAccountResults.$inferInsert

// ============ Relations ============
export const accountsRelations = relations(accounts, ({ many, one }) => ({
  transactions: many(transactions),
  bankConnection: one(bankConnections, {
    fields: [accounts.bankConnectionId],
    references: [bankConnections.id],
  }),
}))

export const bankConnectionsRelations = relations(bankConnections, ({ many }) => ({
  accounts: many(accounts),
}))

export const transactionsRelations = relations(transactions, ({ one }) => ({
  account: one(accounts, {
    fields: [transactions.accountId],
    references: [accounts.id],
  }),
  category: one(categories, {
    fields: [transactions.categoryId],
    references: [categories.id],
  }),
}))

export const categoryGroupsRelations = relations(categoryGroups, ({ many }) => ({
  categories: many(categories),
}))

export const categoriesRelations = relations(categories, ({ one, many }) => ({
  group: one(categoryGroups, {
    fields: [categories.groupId],
    references: [categoryGroups.id],
  }),
  monthlyBudgets: many(monthlyBudgets),
}))

export const monthlyBudgetsRelations = relations(monthlyBudgets, ({ one }) => ({
  category: one(categories, {
    fields: [monthlyBudgets.categoryId],
    references: [categories.id],
  }),
}))
