import {
  boolean,
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

// Export inferred types
export type User = typeof users.$inferSelect
export type NewUser = typeof users.$inferInsert
export type Account = typeof accounts.$inferSelect
export type NewAccount = typeof accounts.$inferInsert
export type CategoryGroup = typeof categoryGroups.$inferSelect
export type Category = typeof categories.$inferSelect
