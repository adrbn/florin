import Database from 'better-sqlite3'
import { drizzle } from 'drizzle-orm/better-sqlite3'
import * as schema from '@florin/db-sqlite/schema'
import type { SqliteDB } from '@florin/db-sqlite'

export interface TestContext {
  raw: Database.Database
  db: SqliteDB
}

/**
 * Spin up an in-memory SQLite database and apply the schema inline.
 * Caller receives both the drizzle wrapper and the raw handle.
 */
export function makeTestDb(): TestContext {
  const raw = new Database(':memory:')
  raw.pragma('journal_mode = MEMORY')
  raw.pragma('foreign_keys = ON')

  raw.exec(`
    CREATE TABLE users (
      id TEXT PRIMARY KEY NOT NULL,
      email TEXT UNIQUE NOT NULL,
      password_hash TEXT NOT NULL,
      locale TEXT NOT NULL DEFAULT 'fr-FR',
      base_currency TEXT NOT NULL DEFAULT 'EUR',
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE bank_connections (
      id TEXT PRIMARY KEY NOT NULL,
      provider TEXT NOT NULL DEFAULT 'enable_banking',
      session_id TEXT UNIQUE NOT NULL,
      aspsp_name TEXT NOT NULL,
      aspsp_country TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'active',
      valid_until TEXT NOT NULL,
      sync_start_date TEXT NOT NULL DEFAULT (datetime('now')),
      last_synced_at TEXT,
      last_sync_error TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE accounts (
      id TEXT PRIMARY KEY NOT NULL,
      name TEXT NOT NULL,
      kind TEXT NOT NULL,
      institution TEXT,
      currency TEXT NOT NULL DEFAULT 'EUR',
      iban TEXT,
      is_active INTEGER NOT NULL DEFAULT 1,
      is_archived INTEGER NOT NULL DEFAULT 0,
      is_included_in_net_worth INTEGER NOT NULL DEFAULT 1,
      current_balance REAL NOT NULL DEFAULT 0,
      last_synced_at TEXT,
      sync_provider TEXT NOT NULL DEFAULT 'manual',
      sync_external_id TEXT,
      bank_connection_id TEXT REFERENCES bank_connections(id) ON DELETE SET NULL,
      display_color TEXT,
      display_icon TEXT,
      display_order INTEGER NOT NULL DEFAULT 0,
      loan_original_principal REAL,
      loan_interest_rate REAL,
      loan_start_date TEXT,
      loan_term_months INTEGER,
      loan_monthly_payment REAL,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE category_groups (
      id TEXT PRIMARY KEY NOT NULL,
      name TEXT UNIQUE NOT NULL,
      kind TEXT NOT NULL,
      display_order INTEGER NOT NULL DEFAULT 0,
      color TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE categories (
      id TEXT PRIMARY KEY NOT NULL,
      group_id TEXT NOT NULL REFERENCES category_groups(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      emoji TEXT,
      display_order INTEGER NOT NULL DEFAULT 0,
      is_fixed INTEGER NOT NULL DEFAULT 0,
      is_archived INTEGER NOT NULL DEFAULT 0,
      linked_loan_account_id TEXT REFERENCES accounts(id) ON DELETE SET NULL,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE UNIQUE INDEX categories_group_name_unique ON categories(group_id, name);
    CREATE TABLE transactions (
      id TEXT PRIMARY KEY NOT NULL,
      account_id TEXT REFERENCES accounts(id) ON DELETE SET NULL,
      occurred_at TEXT NOT NULL,
      recorded_at TEXT NOT NULL DEFAULT (datetime('now')),
      amount REAL NOT NULL,
      currency TEXT NOT NULL DEFAULT 'EUR',
      payee TEXT NOT NULL DEFAULT '',
      normalized_payee TEXT NOT NULL DEFAULT '',
      memo TEXT,
      category_id TEXT REFERENCES categories(id) ON DELETE SET NULL,
      source TEXT NOT NULL,
      external_id TEXT,
      legacy_id TEXT,
      is_pending INTEGER NOT NULL DEFAULT 0,
      needs_review INTEGER NOT NULL DEFAULT 0,
      transfer_pair_id TEXT,
      raw_data TEXT,
      deleted_at TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE monthly_budgets (
      id TEXT PRIMARY KEY NOT NULL,
      year INTEGER NOT NULL,
      month INTEGER NOT NULL,
      category_id TEXT NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
      assigned REAL NOT NULL DEFAULT 0,
      note TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE UNIQUE INDEX monthly_budgets_ymc_unique
      ON monthly_budgets(year, month, category_id);
  `)

  const db = drizzle(raw, { schema }) as unknown as SqliteDB
  return { raw, db }
}

/**
 * Same layout as seedPlanFixture but uses RFC 4122-compliant UUIDs so that
 * mutation tests (which validate categoryId via z.uuid()) can reference them.
 *
 * These are deliberately non-random fixed UUIDs for test determinism.
 */
export function seedMutationFixture(ctx: TestContext) {
  const { raw } = ctx

  // Valid RFC 4122 v4 UUIDs (version nibble = 4, variant nibble = 8)
  const groupSalaryId = 'a1111111-1111-4111-8111-111111111101'
  const groupBillsId =  'a1111111-1111-4111-8111-111111111102'
  const catSalaryId =   'b2222222-2222-4222-8222-222222222201'
  const catRentId =     'b2222222-2222-4222-8222-222222222202'
  const catGroceriesId ='b2222222-2222-4222-8222-222222222203'
  const accountId =     'c3333333-3333-4333-8333-333333333301'

  raw.exec(`
    INSERT INTO category_groups (id, name, kind, display_order) VALUES
      ('${groupSalaryId}', 'Salary', 'income', 0),
      ('${groupBillsId}', 'Bills', 'expense', 1);
    INSERT INTO categories (id, group_id, name, display_order) VALUES
      ('${catSalaryId}', '${groupSalaryId}', 'Paycheck', 0),
      ('${catRentId}', '${groupBillsId}', 'Rent', 0),
      ('${catGroceriesId}', '${groupBillsId}', 'Groceries', 1);
    INSERT INTO accounts (id, name, kind) VALUES
      ('${accountId}', 'Checking', 'checking');
    INSERT INTO transactions (id, account_id, occurred_at, amount, category_id, source, payee) VALUES
      ('d4444444-4444-4444-8444-444444444401', '${accountId}', '2026-04-01', 3000.00, '${catSalaryId}', 'manual', 'Employer'),
      ('d4444444-4444-4444-8444-444444444402', '${accountId}', '2026-04-05', -915.00, '${catRentId}', 'manual', 'Landlord'),
      ('d4444444-4444-4444-8444-444444444403', '${accountId}', '2026-04-10', -50.00, '${catGroceriesId}', 'manual', 'Carrefour'),
      ('d4444444-4444-4444-8444-444444444404', '${accountId}', '2026-04-18', -30.00, '${catGroceriesId}', 'manual', 'Monoprix');
  `)

  return { groupSalaryId, groupBillsId, catSalaryId, catRentId, catGroceriesId, accountId }
}

/**
 * Seed a basic plan-test fixture: 2 groups (one income, one expense),
 * 3 categories, and transactions in April 2026. Returns the IDs so tests
 * can reference them.
 */
export function seedPlanFixture(ctx: TestContext) {
  const { raw } = ctx

  const groupSalaryId = 'grp-salary'
  const groupBillsId = 'grp-bills'
  const catSalaryId = 'cat-salary'
  const catRentId = 'cat-rent'
  const catGroceriesId = 'cat-groceries'
  const accountId = 'acc-checking'

  raw.exec(`
    INSERT INTO category_groups (id, name, kind, display_order) VALUES
      ('${groupSalaryId}', 'Salary', 'income', 0),
      ('${groupBillsId}', 'Bills', 'expense', 1);
    INSERT INTO categories (id, group_id, name, display_order) VALUES
      ('${catSalaryId}', '${groupSalaryId}', 'Paycheck', 0),
      ('${catRentId}', '${groupBillsId}', 'Rent', 0),
      ('${catGroceriesId}', '${groupBillsId}', 'Groceries', 1);
    INSERT INTO accounts (id, name, kind) VALUES
      ('${accountId}', 'Checking', 'checking');
    INSERT INTO transactions (id, account_id, occurred_at, amount, category_id, source, payee) VALUES
      ('tx-income-apr', '${accountId}', '2026-04-01', 3000.00, '${catSalaryId}', 'manual', 'Employer'),
      ('tx-rent-apr', '${accountId}', '2026-04-05', -915.00, '${catRentId}', 'manual', 'Landlord'),
      ('tx-groc-apr-1', '${accountId}', '2026-04-10', -50.00, '${catGroceriesId}', 'manual', 'Carrefour'),
      ('tx-groc-apr-2', '${accountId}', '2026-04-18', -30.00, '${catGroceriesId}', 'manual', 'Monoprix');
  `)

  return { groupSalaryId, groupBillsId, catSalaryId, catRentId, catGroceriesId, accountId }
}
