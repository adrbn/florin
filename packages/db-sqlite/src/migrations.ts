import type Database from 'better-sqlite3'
import { getRawSqlite, type SqliteDB } from './client'

/**
 * Idempotent schema bootstrap.
 *
 * The desktop ships without a dedicated migration runner — existing users
 * have databases created by whichever `drizzle-kit push` snapshot shipped
 * when they first installed. Running `CREATE TABLE IF NOT EXISTS` plus
 * `CREATE INDEX IF NOT EXISTS` on every startup ensures any tables or
 * indexes added to the schema since a user last updated appear without
 * touching rows that already exist.
 *
 * Adding a new column? Append an `ALTER TABLE ... ADD COLUMN` guarded by
 * a `columnExists` check in `addMissingColumns` below.
 */
export function ensureSchema(db: SqliteDB) {
  const sqlite = getRawSqlite(db)

  sqlite.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY NOT NULL,
      email TEXT NOT NULL UNIQUE,
      password_hash TEXT NOT NULL,
      locale TEXT NOT NULL DEFAULT 'fr-FR',
      base_currency TEXT NOT NULL DEFAULT 'EUR',
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS bank_connections (
      id TEXT PRIMARY KEY NOT NULL,
      provider TEXT NOT NULL DEFAULT 'enable_banking',
      session_id TEXT NOT NULL UNIQUE,
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

    CREATE TABLE IF NOT EXISTS accounts (
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
      opening_balance REAL NOT NULL DEFAULT 0,
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

    CREATE TABLE IF NOT EXISTS category_groups (
      id TEXT PRIMARY KEY NOT NULL,
      name TEXT NOT NULL UNIQUE,
      kind TEXT NOT NULL,
      display_order INTEGER NOT NULL DEFAULT 0,
      color TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS categories (
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
    CREATE UNIQUE INDEX IF NOT EXISTS categories_group_name_unique ON categories(group_id, name);

    CREATE TABLE IF NOT EXISTS transactions (
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
    CREATE INDEX IF NOT EXISTS transactions_account_date_idx ON transactions(account_id, occurred_at);
    CREATE INDEX IF NOT EXISTS transactions_category_date_idx ON transactions(category_id, occurred_at);
    CREATE UNIQUE INDEX IF NOT EXISTS transactions_source_external_unique ON transactions(source, external_id) WHERE external_id IS NOT NULL;
    CREATE UNIQUE INDEX IF NOT EXISTS transactions_legacy_unique ON transactions(legacy_id) WHERE legacy_id IS NOT NULL;
    CREATE INDEX IF NOT EXISTS transactions_not_deleted_idx ON transactions(occurred_at) WHERE deleted_at IS NULL;
    CREATE INDEX IF NOT EXISTS transactions_needs_review_idx ON transactions(needs_review) WHERE needs_review = 1;

    CREATE TABLE IF NOT EXISTS balance_snapshots (
      id TEXT PRIMARY KEY NOT NULL,
      snapshot_date TEXT NOT NULL,
      account_id TEXT REFERENCES accounts(id) ON DELETE CASCADE,
      balance REAL NOT NULL,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE UNIQUE INDEX IF NOT EXISTS balance_snapshots_date_account_unique ON balance_snapshots(snapshot_date, account_id);

    CREATE TABLE IF NOT EXISTS categorization_rules (
      id TEXT PRIMARY KEY NOT NULL,
      priority INTEGER NOT NULL DEFAULT 0,
      category_id TEXT NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
      match_payee_regex TEXT,
      match_min_amount REAL,
      match_max_amount REAL,
      match_account_id TEXT REFERENCES accounts(id) ON DELETE CASCADE,
      is_active INTEGER NOT NULL DEFAULT 1,
      hits_count INTEGER NOT NULL DEFAULT 0,
      last_hit_at TEXT,
      note TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS monthly_budgets (
      id TEXT PRIMARY KEY NOT NULL,
      year INTEGER NOT NULL,
      month INTEGER NOT NULL,
      category_id TEXT NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
      assigned REAL NOT NULL DEFAULT 0,
      note TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE UNIQUE INDEX IF NOT EXISTS monthly_budgets_ymc_unique ON monthly_budgets(year, month, category_id);
    CREATE INDEX IF NOT EXISTS monthly_budgets_ym_idx ON monthly_budgets(year, month);

    CREATE TABLE IF NOT EXISTS settings (
      key TEXT PRIMARY KEY NOT NULL,
      value TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS bank_sync_runs (
      id TEXT PRIMARY KEY NOT NULL,
      connection_id TEXT NOT NULL REFERENCES bank_connections(id) ON DELETE CASCADE,
      trigger TEXT NOT NULL DEFAULT 'manual',
      started_at TEXT NOT NULL DEFAULT (datetime('now')),
      finished_at TEXT,
      status TEXT NOT NULL DEFAULT 'running',
      accounts_total INTEGER NOT NULL DEFAULT 0,
      accounts_ok INTEGER NOT NULL DEFAULT 0,
      tx_inserted INTEGER NOT NULL DEFAULT 0,
      error_summary TEXT,
      duration_ms INTEGER
    );
    CREATE INDEX IF NOT EXISTS bank_sync_runs_connection_idx ON bank_sync_runs(connection_id, started_at);
    CREATE INDEX IF NOT EXISTS bank_sync_runs_started_idx ON bank_sync_runs(started_at);

    CREATE TABLE IF NOT EXISTS bank_sync_account_results (
      id TEXT PRIMARY KEY NOT NULL,
      run_id TEXT NOT NULL REFERENCES bank_sync_runs(id) ON DELETE CASCADE,
      account_uid TEXT NOT NULL,
      account_id TEXT REFERENCES accounts(id) ON DELETE SET NULL,
      balance_fetched INTEGER NOT NULL DEFAULT 0,
      balance_error TEXT,
      details_error TEXT,
      tx_fetched INTEGER NOT NULL DEFAULT 0,
      tx_inserted INTEGER NOT NULL DEFAULT 0,
      tx_error TEXT
    );
    CREATE INDEX IF NOT EXISTS bank_sync_account_results_run_idx ON bank_sync_account_results(run_id);
  `)

  addMissingColumns(sqlite)
}

/**
 * Add columns that were introduced after the initial schema snapshot.
 * Uses PRAGMA table_info to check before ALTER — SQLite doesn't support
 * `ADD COLUMN IF NOT EXISTS`.
 */
function addMissingColumns(sqlite: Database.Database) {
  // opening_balance anchor — the invariant going forward is:
  //   current_balance = opening_balance + SUM(non-deleted tx)
  // On first migration we backfill by computing the opening value from the
  // balance that's stored today, so the user's displayed balance is preserved
  // at migration time and future ledger changes move it naturally.
  const added = ensureColumn(sqlite, 'accounts', 'opening_balance', 'REAL NOT NULL DEFAULT 0')
  if (added) {
    sqlite.exec(`
      UPDATE accounts
      SET opening_balance = current_balance - COALESCE(
        (
          SELECT SUM(amount)
          FROM transactions
          WHERE transactions.account_id = accounts.id
            AND transactions.deleted_at IS NULL
        ),
        0
      )
      WHERE sync_provider NOT IN ('enable_banking', 'pytr')
    `)
  }
}

function ensureColumn(
  sqlite: Database.Database,
  table: string,
  column: string,
  definition: string,
): boolean {
  const rows = sqlite.prepare(`PRAGMA table_info(${table})`).all() as Array<{ name: string }>
  if (rows.some((r) => r.name === column)) return false
  sqlite.exec(`ALTER TABLE ${table} ADD COLUMN ${column} ${definition}`)
  return true
}
