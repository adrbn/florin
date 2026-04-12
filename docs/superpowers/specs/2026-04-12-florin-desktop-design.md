# Florin Desktop — Design Spec

## Overview

Electron-based macOS desktop app for Florin, sharing core code with the existing web version via a monorepo. Ships as a `.dmg` with SQLite storage, optional Enable Banking PSD2 sync, menu bar widget, auto-updates, onboarding wizard, and i18n (EN/FR).

## Target Users

- **Lorenzo**: Mac power user, not a developer. Expects drag-to-Applications install.
- **GitHub users**: Open-source audience who want a self-hosted personal finance dashboard without Docker.

## Monorepo Structure

```
florin/
├── packages/
│   ├── core/                  # Shared types, UI components, business logic, i18n
│   │   ├── types/             # Schema types, FlorinQueries/FlorinActions interfaces, DTOs
│   │   ├── components/        # All React UI (dashboard, transactions, accounts, categories, review, reflect, shell)
│   │   ├── lib/               # format/, categorization/, utils
│   │   └── i18n/              # en.json, fr.json, locale helpers
│   ├── db-pg/                 # PostgreSQL Drizzle schema + query/action implementations
│   │   ├── schema.ts          # pgTable definitions (current schema, minimal changes)
│   │   ├── queries/           # Implements FlorinQueries with PG SQL
│   │   ├── actions/           # Implements FlorinActions with PG SQL
│   │   └── migrations/        # Existing Drizzle PG migrations
│   └── db-sqlite/             # SQLite Drizzle schema + query/action implementations
│       ├── schema.ts          # sqliteTable definitions (same shape, SQLite types)
│       ├── queries/           # Implements FlorinQueries with SQLite SQL
│       ├── actions/           # Implements FlorinActions with SQLite SQL
│       └── migrations/        # Fresh Drizzle SQLite migrations
├── apps/
│   ├── web/                   # Adrien's version (Next.js + PostgreSQL + Docker)
│   │   ├── src/app/           # Pages import components from @florin/core
│   │   ├── src/server/        # Auth (NextAuth), banking, env, scheduler
│   │   └── Dockerfile
│   └── desktop/               # Desktop version (Electron + Next.js + SQLite)
│       ├── main/              # Electron main process
│       │   ├── index.ts       # App lifecycle, window management
│       │   ├── tray.ts        # Menu bar tray icon + HTML popup widget
│       │   ├── ipc.ts         # IPC handlers (queries, actions, sync triggers)
│       │   ├── updater.ts     # electron-updater config
│       │   └── scheduler.ts   # Enable Banking sync scheduler (runs in main process)
│       ├── src/app/           # Next.js pages (thin wrappers calling shared components)
│       ├── src/server/        # Simplified auth (optional PIN), banking, env
│       ├── tray-ui/           # HTML/CSS/JS for the tray popup widget
│       └── electron-builder.yml
├── turbo.json                 # Turborepo build config
├── pnpm-workspace.yaml
└── package.json
```

## Database Abstraction Layer

### Query Interface (defined in `@florin/core/types/db.ts`)

```typescript
export interface FlorinQueries {
  getNetWorth(): Promise<NetWorth>
  getMonthBurn(opts?: BurnOptions): Promise<number>
  getAvgMonthlyBurn(months?: number): Promise<number>
  getPatrimonyTimeSeries(months?: number): Promise<PatrimonyPoint[]>
  getMonthByCategory(): Promise<CategoryBreakdownItem[]>
  getTopExpenses(n?: number, days?: number, categoryId?: string | null): Promise<TopExpense[]>
  countUncategorizedExpensesThisMonth(): Promise<number>
  getDataSourceInfo(): Promise<DataSourceInfo>
  getMonthlyFlows(months?: number): Promise<MonthlyFlow[]>
  getSpendingByCategory(months?: number): Promise<CategorySpend[]>
  getCategoryTrend(categoryId: string, months?: number): Promise<MonthlyAmount[]>
  getTransactions(filters: TransactionFilters): Promise<PaginatedResult<Transaction>>
  getFilteredTotal(filters: TransactionFilters): Promise<number>
  countNeedsReview(): Promise<number>
  getAccounts(): Promise<Account[]>
  getAccountDetail(id: string): Promise<Account | null>
  getBankConnections(): Promise<BankConnection[]>
  getCategoryGroups(): Promise<CategoryGroupWithCategories[]>
  getCategorizationRules(): Promise<CategorizationRule[]>
}

export interface FlorinActions {
  createTransaction(data: NewTransaction): Promise<Transaction>
  updateTransaction(id: string, data: Partial<NewTransaction>): Promise<Transaction>
  deleteTransaction(id: string): Promise<void>
  approveTransactions(ids: string[]): Promise<void>
  createAccount(data: NewAccount): Promise<Account>
  updateAccount(id: string, data: Partial<NewAccount>): Promise<Account>
  mergeAccounts(sourceId: string, targetId: string): Promise<void>
  reorderAccounts(ids: string[]): Promise<void>
  createCategory(data: NewCategory): Promise<Category>
  updateCategory(id: string, data: Partial<NewCategory>): Promise<Category>
  deleteCategory(id: string): Promise<void>
  reorderCategories(groupId: string, ids: string[]): Promise<void>
  createCategorizationRule(data: NewCategorizationRule): Promise<CategorizationRule>
  upsertBankConnection(data: NewBankConnection): Promise<BankConnection>
  upsertSyncedAccount(data: SyncedAccountData): Promise<Account>
  upsertSyncedTransactions(data: SyncedTransactionData[]): Promise<number>
}
```

### SQL Dialect Mapping

| PostgreSQL (db-pg) | SQLite (db-sqlite) |
|---|---|
| `to_char(ts, 'YYYY-MM-DD')` | `strftime('%Y-%m-%d', ts)` |
| `to_char(ts, 'YYYY-MM')` | `strftime('%Y-%m', ts)` |
| `::uuid`, `::integer` casts | Omitted (SQLite is typeless) |
| `pgEnum(...)` | `text(...)` (no native enums) |
| `uuid().defaultRandom()` | `text().$defaultFn(() => crypto.randomUUID())` |
| `timestamp with timezone` | `text` (ISO 8601 strings) |
| `numeric(14,2)` | `real` |
| `boolean` | `integer` (0/1) |

### Desktop-Only: `settings` Table

SQLite-only table for desktop app preferences (not in db-pg):

```typescript
// packages/db-sqlite/schema.ts
export const settings = sqliteTable('settings', {
  key: text('key').primaryKey(),        // e.g. 'locale', 'currency', 'pin_hash', 'eb_app_id', 'eb_key_path'
  value: text('value').notNull(),
})
```

Replaces environment variables for desktop — all config lives in the DB, editable through the UI.

Each app wires its DB at startup:
```typescript
// apps/web
import { createPgQueries, createPgActions } from '@florin/db-pg'
export const queries = createPgQueries(pgClient)
export const actions = createPgActions(pgClient)

// apps/desktop
import { createSqliteQueries, createSqliteActions } from '@florin/db-sqlite'
export const queries = createSqliteQueries(sqliteDb)
export const actions = createSqliteActions(sqliteDb)
```

## Electron Shell

### Main Process

- Starts custom Next.js server on a random available port
- Creates `BrowserWindow` pointed at `http://localhost:<port>`
- Creates `Tray` with HTML popup window (320px wide, rich dashboard style)
- Runs Enable Banking sync scheduler (survives window close)
- Handles auto-update checks via `electron-updater`
- SQLite DB at `~/Library/Application Support/Florin/florin.db`

### Tray Widget (HTML Popup)

Rich dashboard popup (320px, dark theme) showing:
- Net worth with mini sparkline + month-over-month delta
- Burn rate + budget remaining with progress bar
- Recent transactions (last 3-5) with category color dots and labels
- Quick actions: Sync, Add Transaction, Open Dashboard
- Sync status indicator (green dot = synced, yellow = syncing, red = error)

Data fetched via IPC from the running Next.js server, refreshed on tray open + after sync.

### Window Management

- Closing the window hides it (app stays in tray)
- Cmd+Q or tray "Quit" exits the app
- Dock icon optional (can run as menu bar-only app)

## Onboarding Flow

Six-step wizard shown on first launch (no existing data detected):

1. **Welcome** — "Florin — Your finances, your machine." Brief value prop.
2. **Locale & Currency** — Pick language (EN/FR), base currency (EUR/GBP/USD/CHF). Affects all formatting and seed data.
3. **Enable Banking Setup** (optional) — Explains PSD2 bank sync, links to Enable Banking registration page, file drop for RSA private key, text field for App ID. Prominent "Skip for now" button. Can be configured later in Settings.
4. **Category Seed Preview** — Shows default categories in chosen language. User can rename, delete, add, reorder before confirming.
5. **First Account** — If EB configured: option to connect bank immediately. Otherwise: create manual account (name, type, starting balance).
6. **Interactive Tutorial** — Tooltip walkthrough of the dashboard: net worth KPI, burn rate, patrimony chart, sidebar navigation, "add transaction" button, tray widget. Dismissable, can be replayed from Settings.

## Auth

- **No login by default** — app opens straight to dashboard (or onboarding on first launch)
- **Optional PIN** — configurable in Settings. Stored as bcrypt hash in SQLite `settings` table.
- When enabled: PIN entry screen on app launch before loading dashboard.

## Enable Banking in Desktop

- Same `enable-banking.ts` client as web (RSA JWT signing, session management, transaction fetch)
- Credentials stored in SQLite `settings` table (app_id) + file system (private key in `~/Library/Application Support/Florin/`)
- Not environment variables — configured through the UI (onboarding or Settings)
- Sync scheduler in Electron main process: 6-hour interval, 2-minute warmup on launch
- Tray icon reflects sync state: green dot (synced), yellow (syncing), red (last sync failed)
- "Sync Now" available in tray widget and dashboard

## Auto-Update

- `electron-updater` checks GitHub Releases on launch + every 6 hours
- Notification in tray widget: "Update available (v1.2.0)" with download button
- Downloads in background, prompts restart when ready
- GitHub Actions workflow: push tag `desktop-v*` → build universal macOS `.dmg` (Intel + Apple Silicon) → upload to GitHub Release
- No code signing initially (user will see Gatekeeper warning on first launch — acceptable for open-source)

## i18n

- `packages/core/i18n/en.json` and `fr.json` — flat key-value structure
- Covers: all UI strings, category seed names, onboarding text, tutorial tooltips, tray widget labels
- Locale stored in SQLite `settings` table, chosen during onboarding
- Number/date/currency formatting via `Intl.NumberFormat` / `Intl.DateTimeFormat` with stored locale
- Adding a language = adding a JSON file + updating the locale picker

## What Ships Where

| Feature | Web (apps/web) | Desktop (apps/desktop) |
|---|---|---|
| Dashboard, Transactions, Accounts, Categories, Review, Reflect | Yes | Yes |
| Enable Banking PSD2 | Yes | Yes |
| Categorization rules | Yes | Yes |
| Dark/light mode | Yes | Yes |
| i18n (EN/FR) | Yes | Yes |
| PostgreSQL | Yes | No |
| SQLite | No | Yes |
| Docker / compose.yaml | Yes | No |
| Makefile deploy targets | Yes | No |
| Legacy XLSX import | Yes | No |
| NextAuth (email/password) | Yes | No |
| Optional PIN auth | No | Yes |
| Menu bar tray widget | No | Yes |
| Auto-updater | No | Yes |
| Onboarding wizard + tutorial | No | Yes |
| electron-builder / .dmg | No | Yes |
| GitHub Actions CI for releases | Docker build (existing) | .dmg build (new) |

## Tech Stack Additions

| Package | Purpose |
|---|---|
| `electron` | Desktop shell |
| `electron-builder` | Package as .dmg |
| `electron-updater` | Auto-update from GitHub Releases |
| `better-sqlite3` | SQLite driver for Node.js |
| `drizzle-orm/better-sqlite3` | Drizzle SQLite adapter |
| `turborepo` | Monorepo build orchestration |
