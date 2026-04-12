import { randomUUID } from 'node:crypto'
import { relations, sql } from 'drizzle-orm'
import {
  index,
  integer,
  real,
  sqliteTable,
  text,
  uniqueIndex,
} from 'drizzle-orm/sqlite-core'

// ============ users ============
export const users = sqliteTable('users', {
  id: text('id')
    .primaryKey()
    .$defaultFn(() => randomUUID()),
  email: text('email').notNull().unique(),
  passwordHash: text('password_hash').notNull(),
  locale: text('locale').notNull().default('fr-FR'),
  baseCurrency: text('base_currency').notNull().default('EUR'),
  createdAt: text('created_at')
    .notNull()
    .default(sql`(datetime('now'))`),
  updatedAt: text('updated_at')
    .notNull()
    .default(sql`(datetime('now'))`),
})

// ============ bank_connections ============
export const bankConnections = sqliteTable('bank_connections', {
  id: text('id')
    .primaryKey()
    .$defaultFn(() => randomUUID()),
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
  validUntil: text('valid_until').notNull(),
  /**
   * Lower bound for transaction sync. Never fetch transactions dated before
   * this. Defaults to the connection creation date so the first sync doesn't
   * pull history that might overlap with legacy XLSX imports. User can move
   * this earlier (down to 90 days ago) or later as needed.
   */
  syncStartDate: text('sync_start_date')
    .notNull()
    .default(sql`(datetime('now'))`),
  /** Last successful sync across all accounts in this connection. */
  lastSyncedAt: text('last_synced_at'),
  /** Human-readable error from the last failed sync (for display in /accounts). */
  lastSyncError: text('last_sync_error'),
  createdAt: text('created_at')
    .notNull()
    .default(sql`(datetime('now'))`),
  updatedAt: text('updated_at')
    .notNull()
    .default(sql`(datetime('now'))`),
})

// ============ accounts ============
export const accounts = sqliteTable('accounts', {
  id: text('id')
    .primaryKey()
    .$defaultFn(() => randomUUID()),
  name: text('name').notNull(),
  /** One of: checking, savings, cash, loan, broker_cash, broker_portfolio, other */
  kind: text('kind').notNull(),
  institution: text('institution'),
  currency: text('currency').notNull().default('EUR'),
  iban: text('iban'),
  isActive: integer('is_active', { mode: 'boolean' }).notNull().default(true),
  isArchived: integer('is_archived', { mode: 'boolean' }).notNull().default(false),
  isIncludedInNetWorth: integer('is_included_in_net_worth', { mode: 'boolean' })
    .notNull()
    .default(true),
  currentBalance: real('current_balance').notNull().default(0),
  lastSyncedAt: text('last_synced_at'),
  /** One of: enable_banking, pytr, manual, legacy */
  syncProvider: text('sync_provider').notNull().default('manual'),
  syncExternalId: text('sync_external_id'),
  /** FK to bank_connections when syncProvider = 'enable_banking'. Null for manual/legacy. */
  bankConnectionId: text('bank_connection_id').references(() => bankConnections.id, {
    onDelete: 'set null',
  }),
  displayColor: text('display_color'),
  displayIcon: text('display_icon'),
  displayOrder: integer('display_order').notNull().default(0),
  // Loan-specific fields
  loanOriginalPrincipal: real('loan_original_principal'),
  loanInterestRate: real('loan_interest_rate'),
  loanStartDate: text('loan_start_date'),
  loanTermMonths: integer('loan_term_months'),
  loanMonthlyPayment: real('loan_monthly_payment'),
  createdAt: text('created_at')
    .notNull()
    .default(sql`(datetime('now'))`),
  updatedAt: text('updated_at')
    .notNull()
    .default(sql`(datetime('now'))`),
})

// ============ category_groups ============
export const categoryGroups = sqliteTable('category_groups', {
  id: text('id')
    .primaryKey()
    .$defaultFn(() => randomUUID()),
  name: text('name').notNull().unique(),
  /** One of: income, expense */
  kind: text('kind').notNull(),
  displayOrder: integer('display_order').notNull().default(0),
  color: text('color'),
  createdAt: text('created_at')
    .notNull()
    .default(sql`(datetime('now'))`),
})

// ============ categories ============
export const categories = sqliteTable(
  'categories',
  {
    id: text('id')
      .primaryKey()
      .$defaultFn(() => randomUUID()),
    groupId: text('group_id')
      .notNull()
      .references(() => categoryGroups.id, { onDelete: 'cascade' }),
    name: text('name').notNull(),
    emoji: text('emoji'),
    displayOrder: integer('display_order').notNull().default(0),
    isFixed: integer('is_fixed', { mode: 'boolean' }).notNull().default(false),
    isArchived: integer('is_archived', { mode: 'boolean' }).notNull().default(false),
    /**
     * Optional link to a loan account. When a transaction is categorized
     * into a category that has this set, the loan account's currentBalance
     * gets reduced by |amount| automatically.
     */
    linkedLoanAccountId: text('linked_loan_account_id').references(() => accounts.id, {
      onDelete: 'set null',
    }),
    createdAt: text('created_at')
      .notNull()
      .default(sql`(datetime('now'))`),
  },
  (t) => [uniqueIndex('categories_group_name_unique').on(t.groupId, t.name)],
)

// ============ transactions ============
export const transactions = sqliteTable(
  'transactions',
  {
    id: text('id')
      .primaryKey()
      .$defaultFn(() => randomUUID()),
    accountId: text('account_id')
      .notNull()
      .references(() => accounts.id, { onDelete: 'cascade' }),
    occurredAt: text('occurred_at').notNull(),
    recordedAt: text('recorded_at')
      .notNull()
      .default(sql`(datetime('now'))`),
    amount: real('amount').notNull(),
    currency: text('currency').notNull().default('EUR'),
    payee: text('payee').notNull().default(''),
    normalizedPayee: text('normalized_payee').notNull().default(''),
    memo: text('memo'),
    categoryId: text('category_id').references(() => categories.id, { onDelete: 'set null' }),
    /** One of: enable_banking, pytr, manual, legacy_xlsx, ios_shortcut */
    source: text('source').notNull(),
    externalId: text('external_id'),
    legacyId: text('legacy_id'),
    isPending: integer('is_pending', { mode: 'boolean' }).notNull().default(false),
    needsReview: integer('needs_review', { mode: 'boolean' }).notNull().default(false),
    transferPairId: text('transfer_pair_id'),
    rawData: text('raw_data'),
    deletedAt: text('deleted_at'),
    createdAt: text('created_at')
      .notNull()
      .default(sql`(datetime('now'))`),
    updatedAt: text('updated_at')
      .notNull()
      .default(sql`(datetime('now'))`),
  },
  (t) => [
    index('transactions_account_date_idx').on(t.accountId, t.occurredAt),
    index('transactions_category_date_idx').on(t.categoryId, t.occurredAt),
    uniqueIndex('transactions_source_external_unique')
      .on(t.source, t.externalId)
      .where(sql`${t.externalId} IS NOT NULL`),
    uniqueIndex('transactions_legacy_unique').on(t.legacyId).where(sql`${t.legacyId} IS NOT NULL`),
    index('transactions_not_deleted_idx').on(t.occurredAt).where(sql`${t.deletedAt} IS NULL`),
    index('transactions_needs_review_idx').on(t.needsReview).where(sql`${t.needsReview} = 1`),
  ],
)

// ============ balance_snapshots ============
export const balanceSnapshots = sqliteTable(
  'balance_snapshots',
  {
    id: text('id')
      .primaryKey()
      .$defaultFn(() => randomUUID()),
    snapshotDate: text('snapshot_date').notNull(),
    accountId: text('account_id').references(() => accounts.id, { onDelete: 'cascade' }),
    balance: real('balance').notNull(),
    createdAt: text('created_at')
      .notNull()
      .default(sql`(datetime('now'))`),
  },
  (t) => [uniqueIndex('balance_snapshots_date_account_unique').on(t.snapshotDate, t.accountId)],
)

// ============ categorization_rules ============
export const categorizationRules = sqliteTable('categorization_rules', {
  id: text('id')
    .primaryKey()
    .$defaultFn(() => randomUUID()),
  priority: integer('priority').notNull().default(0),
  categoryId: text('category_id')
    .notNull()
    .references(() => categories.id, { onDelete: 'cascade' }),
  matchPayeeRegex: text('match_payee_regex'),
  matchMinAmount: real('match_min_amount'),
  matchMaxAmount: real('match_max_amount'),
  matchAccountId: text('match_account_id').references(() => accounts.id, { onDelete: 'cascade' }),
  isActive: integer('is_active', { mode: 'boolean' }).notNull().default(true),
  hitsCount: integer('hits_count').notNull().default(0),
  lastHitAt: text('last_hit_at'),
  note: text('note'),
  createdAt: text('created_at')
    .notNull()
    .default(sql`(datetime('now'))`),
  updatedAt: text('updated_at')
    .notNull()
    .default(sql`(datetime('now'))`),
})

// ============ settings (desktop-only) ============
export const settings = sqliteTable('settings', {
  key: text('key').primaryKey(),
  value: text('value').notNull(),
})

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
export type Setting = typeof settings.$inferSelect

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

export const categoriesRelations = relations(categories, ({ one }) => ({
  group: one(categoryGroups, {
    fields: [categories.groupId],
    references: [categoryGroups.id],
  }),
}))
