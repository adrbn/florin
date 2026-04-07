import { sql } from 'drizzle-orm'
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
  lastSyncedAt: timestamp('last_synced_at', { withTimezone: true }),
  syncProvider: syncProviderEnum('sync_provider').notNull().default('manual'),
  syncExternalId: text('sync_external_id'),
  displayColor: text('display_color'),
  displayIcon: text('display_icon'),
  displayOrder: integer('display_order').notNull().default(0),
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
    createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  },
  (t) => [uniqueIndex('categories_group_name_unique').on(t.groupId, t.name)],
)

// ============ transactions ============
export const transactions = pgTable(
  'transactions',
  {
    id: uuid('id').primaryKey().defaultRandom(),
    accountId: uuid('account_id')
      .notNull()
      .references(() => accounts.id, { onDelete: 'cascade' }),
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

// Export inferred types
export type User = typeof users.$inferSelect
export type NewUser = typeof users.$inferInsert
export type Account = typeof accounts.$inferSelect
export type NewAccount = typeof accounts.$inferInsert
export type CategoryGroup = typeof categoryGroups.$inferSelect
export type Category = typeof categories.$inferSelect
export type Transaction = typeof transactions.$inferSelect
export type NewTransaction = typeof transactions.$inferInsert
export type BalanceSnapshot = typeof balanceSnapshots.$inferSelect
export type CategorizationRule = typeof categorizationRules.$inferSelect
export type NewCategorizationRule = typeof categorizationRules.$inferInsert
