import Foundation

/// The ledger schema, on the device.
///
/// This is not a hand-written translation of \`packages/db-sqlite/schema.ts\` —
/// it is the DDL SQLite itself reports for a database that package created, so
/// the phone and the desktop cannot drift on a column type or a partial index.
/// Regenerate it with \`sqlite3 florin.db .schema\` against a desktop install
/// rather than editing it by hand.
///
/// Every statement is \`IF NOT EXISTS\`: \`migrate()\` runs on every launch and
/// must be a no-op on the second one.
enum LocalSchema {
    /// Bumped whenever the statements below change, so a future migration can
    /// tell what shape it is upgrading from.
    static let version = 1

    static let ddl = """
        CREATE TABLE IF NOT EXISTS users (
            id TEXT PRIMARY KEY,
            email TEXT NOT NULL UNIQUE,
            password_hash TEXT NOT NULL,
            locale TEXT NOT NULL DEFAULT 'fr-FR',
            base_currency TEXT NOT NULL DEFAULT 'EUR',
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
          );
        CREATE TABLE IF NOT EXISTS bank_connections (
            id TEXT PRIMARY KEY,
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
            id TEXT PRIMARY KEY,
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
          , opening_balance REAL NOT NULL DEFAULT 0, market_value REAL NOT NULL DEFAULT 0);
        CREATE TABLE IF NOT EXISTS category_groups (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL UNIQUE,
            kind TEXT NOT NULL,
            display_order INTEGER NOT NULL DEFAULT 0,
            color TEXT,
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
          );
        CREATE TABLE IF NOT EXISTS categories (
            id TEXT PRIMARY KEY,
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
            id TEXT PRIMARY KEY,
            account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
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
          , status TEXT NOT NULL DEFAULT 'cleared', recurring_rule_id TEXT, recurrence_key TEXT, merge_suggested_tx_id TEXT);
        CREATE INDEX IF NOT EXISTS transactions_account_date_idx ON transactions(account_id, occurred_at);
        CREATE INDEX IF NOT EXISTS transactions_category_date_idx ON transactions(category_id, occurred_at);
        CREATE TABLE IF NOT EXISTS balance_snapshots (
            id TEXT PRIMARY KEY,
            snapshot_date TEXT NOT NULL,
            account_id TEXT REFERENCES accounts(id) ON DELETE CASCADE,
            balance REAL NOT NULL,
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
          );
        CREATE UNIQUE INDEX IF NOT EXISTS balance_snapshots_date_account_unique ON balance_snapshots(snapshot_date, account_id);
        CREATE TABLE IF NOT EXISTS categorization_rules (
            id TEXT PRIMARY KEY,
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
        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          );
        CREATE UNIQUE INDEX IF NOT EXISTS transactions_source_external_unique ON transactions(source, external_id) WHERE external_id IS NOT NULL;
        CREATE UNIQUE INDEX IF NOT EXISTS transactions_legacy_unique ON transactions(legacy_id) WHERE legacy_id IS NOT NULL;
        CREATE INDEX IF NOT EXISTS transactions_not_deleted_idx ON transactions(occurred_at) WHERE deleted_at IS NULL;
        CREATE INDEX IF NOT EXISTS transactions_needs_review_idx ON transactions(needs_review) WHERE needs_review = 1;
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
        CREATE TABLE IF NOT EXISTS recurring_rules (
              id TEXT PRIMARY KEY NOT NULL,
              name TEXT NOT NULL,
              kind TEXT NOT NULL DEFAULT 'transfer',
              account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
              to_account_id TEXT REFERENCES accounts(id) ON DELETE CASCADE,
              amount REAL NOT NULL,
              payee TEXT NOT NULL DEFAULT '',
              category_id TEXT REFERENCES categories(id) ON DELETE SET NULL,
              currency TEXT NOT NULL DEFAULT 'EUR',
              memo TEXT,
              frequency TEXT NOT NULL DEFAULT 'monthly',
              interval INTEGER NOT NULL DEFAULT 1,
              day_of_month INTEGER NOT NULL DEFAULT 1,
              start_date TEXT NOT NULL,
              end_date TEXT,
              is_active INTEGER NOT NULL DEFAULT 1,
              last_materialized_date TEXT,
              created_at TEXT NOT NULL DEFAULT (datetime('now')),
              updated_at TEXT NOT NULL DEFAULT (datetime('now'))
            );
        CREATE INDEX IF NOT EXISTS recurring_rules_active_idx ON recurring_rules(is_active);
        CREATE INDEX IF NOT EXISTS recurring_rules_account_idx ON recurring_rules(account_id);
        CREATE TABLE IF NOT EXISTS holdings (
              id TEXT PRIMARY KEY NOT NULL,
              account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
              label TEXT NOT NULL,
              isin TEXT,
              quote_symbol TEXT,
              quantity REAL NOT NULL DEFAULT 0,
              cost_basis REAL NOT NULL DEFAULT 0,
              currency TEXT NOT NULL DEFAULT 'EUR',
              last_price REAL,
              last_price_at TEXT,
              created_at TEXT NOT NULL DEFAULT (datetime('now')),
              updated_at TEXT NOT NULL DEFAULT (datetime('now'))
            );
        CREATE INDEX IF NOT EXISTS holdings_account_idx ON holdings(account_id);
        CREATE INDEX IF NOT EXISTS transactions_status_idx ON transactions(status, occurred_at) WHERE deleted_at IS NULL;
        CREATE INDEX IF NOT EXISTS transactions_recurring_rule_idx ON transactions(recurring_rule_id) WHERE recurring_rule_id IS NOT NULL;
        CREATE UNIQUE INDEX IF NOT EXISTS transactions_recurrence_key_unique ON transactions(recurrence_key, account_id) WHERE recurrence_key IS NOT NULL;
        """
}
