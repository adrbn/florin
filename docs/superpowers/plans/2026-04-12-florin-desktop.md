# Florin Desktop — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create an Electron-based macOS desktop app for Florin with SQLite, menu bar widget, Enable Banking sync, auto-updates, onboarding, and i18n — sharing core code with the existing web version via a monorepo.

**Architecture:** Monorepo with pnpm workspaces + Turborepo. Shared `@florin/core` (types, components, i18n), dialect-specific `@florin/db-pg` and `@florin/db-sqlite`, and two apps: `apps/web` (existing, PostgreSQL) and `apps/desktop` (Electron + SQLite). The DB abstraction is a TypeScript interface (`FlorinQueries` / `FlorinActions`) with implementations per dialect.

**Tech Stack:** Electron 35, electron-builder, electron-updater, better-sqlite3, drizzle-orm (pg + better-sqlite3), Next.js 15, React 19, Tailwind 4, Turborepo, pnpm workspaces.

**Decomposition:** This plan is split into 4 phases. Each phase produces working, testable software.

- **Phase 1** — Monorepo scaffolding + DB abstraction layer + extract `@florin/core`
- **Phase 2** — Electron shell + desktop app with SQLite + tray widget
- **Phase 3** — Onboarding wizard, i18n, tutorial, optional PIN auth
- **Phase 4** — Auto-updater, GitHub Actions CI, packaging, distribution

---

## Phase 1: Monorepo + DB Abstraction + Core Extraction

### Task 1: Scaffold monorepo with pnpm workspaces + Turborepo

**Files:**
- Create: `pnpm-workspace.yaml`
- Create: `turbo.json`
- Modify: `package.json` (root — add turbo, workspace config)

- [ ] **Step 1: Create `pnpm-workspace.yaml`**

```yaml
packages:
  - "apps/*"
  - "packages/*"
```

- [ ] **Step 2: Create root `turbo.json`**

```json
{
  "$schema": "https://turbo.build/schema.json",
  "tasks": {
    "build": {
      "dependsOn": ["^build"],
      "outputs": [".next/**", "dist/**"]
    },
    "dev": {
      "cache": false,
      "persistent": true
    },
    "lint": {
      "dependsOn": ["^build"]
    },
    "test": {
      "dependsOn": ["^build"]
    }
  }
}
```

- [ ] **Step 3: Update root `package.json`**

Add `turbo` as a devDependency. Add scripts:
```json
{
  "scripts": {
    "dev": "turbo dev",
    "build": "turbo build",
    "lint": "turbo lint",
    "test": "turbo test"
  },
  "devDependencies": {
    "turbo": "^2.5.0"
  }
}
```

- [ ] **Step 4: Install and verify**

Run: `pnpm install`
Run: `pnpm turbo build --dry-run`
Expected: Turbo recognizes `apps/web` as a workspace package.

- [ ] **Step 5: Commit**

```bash
git add pnpm-workspace.yaml turbo.json package.json pnpm-lock.yaml
git commit -m "chore: scaffold monorepo with pnpm workspaces + turborepo"
```

---

### Task 2: Create `@florin/core` package — types and query interfaces

**Files:**
- Create: `packages/core/package.json`
- Create: `packages/core/tsconfig.json`
- Create: `packages/core/src/types/db.ts` (FlorinQueries + FlorinActions interfaces)
- Create: `packages/core/src/types/models.ts` (shared model types extracted from schema)
- Create: `packages/core/src/types/index.ts` (barrel export)
- Create: `packages/core/src/index.ts` (package entry)

- [ ] **Step 1: Create `packages/core/package.json`**

```json
{
  "name": "@florin/core",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "exports": {
    ".": "./src/index.ts",
    "./types": "./src/types/index.ts"
  },
  "dependencies": {
    "zod": "^4.3.6"
  },
  "devDependencies": {
    "typescript": "^6.0.2"
  }
}
```

- [ ] **Step 2: Create `packages/core/tsconfig.json`**

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "declaration": true,
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "outDir": "dist",
    "rootDir": "src"
  },
  "include": ["src"]
}
```

- [ ] **Step 3: Create `packages/core/src/types/models.ts`**

Extract the shared model types from the current schema. These are DB-agnostic shapes that both apps and both DB packages use:

```typescript
// Shared model types — DB-agnostic. Derived from the Drizzle schema
// select types but declared independently so @florin/core has no
// dependency on drizzle-orm or any dialect-specific package.

export type AccountKind =
  | 'checking'
  | 'savings'
  | 'cash'
  | 'loan'
  | 'broker_cash'
  | 'broker_portfolio'
  | 'other'

export type SyncProvider = 'enable_banking' | 'pytr' | 'manual' | 'legacy'
export type CategoryKind = 'income' | 'expense'
export type TransactionSource =
  | 'enable_banking'
  | 'pytr'
  | 'manual'
  | 'legacy_xlsx'
  | 'ios_shortcut'

export interface Account {
  id: string
  name: string
  kind: AccountKind
  institution: string | null
  currency: string
  iban: string | null
  isActive: boolean
  isArchived: boolean
  isIncludedInNetWorth: boolean
  currentBalance: string
  lastSyncedAt: Date | null
  syncProvider: SyncProvider
  syncExternalId: string | null
  bankConnectionId: string | null
  displayColor: string | null
  displayIcon: string | null
  displayOrder: number
  loanOriginalPrincipal: string | null
  loanInterestRate: string | null
  loanStartDate: Date | null
  loanTermMonths: number | null
  loanMonthlyPayment: string | null
  createdAt: Date
  updatedAt: Date
}

export interface BankConnection {
  id: string
  provider: string
  sessionId: string
  aspspName: string
  aspspCountry: string
  status: string
  validUntil: Date
  syncStartDate: Date
  lastSyncedAt: Date | null
  lastSyncError: string | null
  createdAt: Date
  updatedAt: Date
}

export interface CategoryGroup {
  id: string
  name: string
  kind: CategoryKind
  displayOrder: number
  color: string | null
  createdAt: Date
}

export interface Category {
  id: string
  groupId: string
  name: string
  emoji: string | null
  displayOrder: number
  isFixed: boolean
  isArchived: boolean
  linkedLoanAccountId: string | null
  createdAt: Date
}

export interface Transaction {
  id: string
  accountId: string
  occurredAt: Date
  recordedAt: Date
  amount: string
  currency: string
  payee: string
  normalizedPayee: string
  memo: string | null
  categoryId: string | null
  source: TransactionSource
  externalId: string | null
  legacyId: string | null
  isPending: boolean
  needsReview: boolean
  transferPairId: string | null
  rawData: string | null
  deletedAt: Date | null
  createdAt: Date
  updatedAt: Date
}

export interface CategorizationRule {
  id: string
  priority: number
  categoryId: string
  matchPayeeRegex: string | null
  matchMinAmount: string | null
  matchMaxAmount: string | null
  matchAccountId: string | null
  isActive: boolean
  hitsCount: number
  lastHitAt: Date | null
  note: string | null
  createdAt: Date
  updatedAt: Date
}

export interface BalanceSnapshot {
  id: string
  snapshotDate: Date
  accountId: string | null
  balance: string
  createdAt: Date
}

// Composite types used by queries
export interface CategoryGroupWithCategories extends CategoryGroup {
  categories: Category[]
}

export interface TransactionWithRelations extends Transaction {
  account: Account
  category: Category | null
}
```

- [ ] **Step 4: Create `packages/core/src/types/db.ts`**

The query and action interfaces:

```typescript
import type {
  Account,
  BankConnection,
  CategoryGroupWithCategories,
  CategorizationRule,
  TransactionWithRelations,
} from './models'

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
  startDate?: Date
  endDate?: Date
  direction?: TransactionDirection
  excludeTransfers?: boolean
  payeeSearch?: string
  categoryId?: string | 'none'
  minAmount?: number
  maxAmount?: number
}

export interface PaginatedResult<T> {
  rows: T[]
  total: number
}

// ============ Query interface ============

export interface FlorinQueries {
  // Dashboard
  getNetWorth(): Promise<NetWorth>
  getMonthBurn(opts?: BurnOptions): Promise<number>
  getAvgMonthlyBurn(months?: number): Promise<number>
  getPatrimonyTimeSeries(months?: number): Promise<PatrimonyPoint[]>
  getMonthByCategory(): Promise<CategoryBreakdownItem[]>
  getTopExpenses(n?: number, days?: number, categoryId?: string | null): Promise<TopExpense[]>
  countUncategorizedExpensesThisMonth(): Promise<number>
  getDataSourceInfo(): Promise<DataSourceInfo>

  // Reflect
  getMonthlyFlows(months?: number): Promise<MonthlyFlow[]>
  getCategoryBreakdown(days?: number): Promise<CategoryShare[]>
  getAgeOfMoney(days?: number): Promise<number | null>
  getNetWorthSeries(months?: number): Promise<NetWorthPoint[]>

  // Transactions
  listTransactions(options?: ListTransactionsOptions): Promise<TransactionWithRelations[]>
  countTransactions(options?: ListTransactionsOptions): Promise<number>
  countNeedsReview(): Promise<number>

  // Accounts
  listAccounts(options?: { includeArchived?: boolean }): Promise<Account[]>
  getAccountById(id: string): Promise<(Account & { bankConnection?: BankConnection | null }) | null>
  listBankConnections(): Promise<BankConnection[]>

  // Categories
  listCategoriesByGroup(): Promise<CategoryGroupWithCategories[]>
  listCategoriesFlat(): Promise<Array<{
    id: string
    name: string
    emoji: string | null
    groupName: string
    linkedLoanAccountId: string | null
  }>>
  listCategorizationRules(): Promise<CategorizationRule[]>
}

// ============ Action result ============

export interface ActionResult<T = void> {
  success: boolean
  error?: string
  data?: T
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

// ============ Action interface ============
// Note: Actions that call revalidatePath are Next.js-specific and live
// in each app's server layer. The interface below covers the data
// mutations only — each app wraps these with its own cache invalidation.

export interface FlorinMutations {
  createAccount(input: CreateAccountInput): Promise<ActionResult<{ id: string }>>
  updateAccount(input: UpdateAccountInput): Promise<ActionResult>
  deleteAccount(id: string): Promise<ActionResult>
  setAccountArchived(id: string, archived: boolean): Promise<ActionResult>
  reorderAccounts(orderedIds: string[]): Promise<ActionResult>
  mergeAccount(sourceId: string, targetId: string): Promise<ActionResult>
  updateLoanSettings(input: LoanSettingsInput): Promise<ActionResult>

  addTransaction(input: AddTransactionInput): Promise<ActionResult<{ id: string }>>
  updateTransactionCategory(transactionId: string, categoryId: string | null): Promise<ActionResult>
  softDeleteTransaction(id: string): Promise<ActionResult>
  approveTransaction(transactionId: string): Promise<ActionResult>
  approveAllTransactions(): Promise<ActionResult<{ approved: number }>>
  bulkUpdateTransactionCategory(ids: string[], categoryId: string | null): Promise<ActionResult<{ updated: number }>>
  bulkApproveTransactions(ids: string[]): Promise<ActionResult<{ approved: number }>>
  bulkSoftDeleteTransactions(ids: string[]): Promise<ActionResult<{ deleted: number }>>

  createCategory(input: CreateCategoryInput): Promise<ActionResult<{ id: string }>>
  updateCategory(input: UpdateCategoryInput): Promise<ActionResult>
  deleteCategory(id: string): Promise<ActionResult>
  createCategoryGroup(input: CreateGroupInput): Promise<ActionResult<{ id: string }>>
  updateCategoryGroup(input: CreateGroupInput & { id: string }): Promise<ActionResult>
  deleteCategoryGroup(id: string): Promise<ActionResult>
  setCategoryLoanLink(categoryId: string, loanAccountId: string | null): Promise<ActionResult<{ touched: number }>>
}
```

- [ ] **Step 5: Create barrel exports**

`packages/core/src/types/index.ts`:
```typescript
export * from './models'
export * from './db'
```

`packages/core/src/index.ts`:
```typescript
export * from './types'
```

- [ ] **Step 6: Install deps and verify**

Run: `cd packages/core && pnpm install`
Run: `pnpm tsc --noEmit` from `packages/core`
Expected: Clean compilation with no errors.

- [ ] **Step 7: Commit**

```bash
git add packages/core/
git commit -m "feat(core): add @florin/core package with shared types and query interfaces"
```

---

### Task 3: Extract shared lib code to `@florin/core`

**Files:**
- Move: `apps/web/src/lib/format/currency.ts` → `packages/core/src/lib/format/currency.ts`
- Move: `apps/web/src/lib/categorization/` → `packages/core/src/lib/categorization/`
- Move: `apps/web/src/lib/loan/` → `packages/core/src/lib/loan/`
- Move: `apps/web/src/lib/utils.ts` → `packages/core/src/lib/utils.ts`
- Modify: `packages/core/package.json` (add lib exports)
- Modify: `apps/web/src/lib/` (replace with re-exports from `@florin/core`)

- [ ] **Step 1: Move lib files to core**

Copy the following to `packages/core/src/lib/`:
- `format/currency.ts` — make locale/currency configurable (accept params instead of hardcoded `fr-FR` + `EUR`)
- `categorization/engine.ts` + `categorization/normalize-payee.ts`
- `loan/liability.ts`
- `utils.ts` (cn helper, etc.)

For `currency.ts`, refactor the hardcoded formatters to be factory functions:

```typescript
export function createCurrencyFormatter(locale: string, currency: string) {
  const formatter = new Intl.NumberFormat(locale, {
    style: 'currency',
    currency,
  })
  const signedFormatter = new Intl.NumberFormat(locale, {
    style: 'currency',
    currency,
    signDisplay: 'always',
  })
  return {
    format: (amount: number | string | null | undefined) => formatter.format(toNumber(amount)),
    formatSigned: (amount: number | string | null | undefined) => signedFormatter.format(toNumber(amount)),
  }
}

function toNumber(amount: number | string | null | undefined): number {
  if (amount === null || amount === undefined) return 0
  if (typeof amount === 'number') return amount
  const parsed = Number(amount)
  return Number.isFinite(parsed) ? parsed : 0
}
```

- [ ] **Step 2: Update `packages/core/package.json` exports**

```json
{
  "exports": {
    ".": "./src/index.ts",
    "./types": "./src/types/index.ts",
    "./lib/format": "./src/lib/format/currency.ts",
    "./lib/categorization": "./src/lib/categorization/index.ts",
    "./lib/loan": "./src/lib/loan/liability.ts",
    "./lib/utils": "./src/lib/utils.ts"
  }
}
```

- [ ] **Step 3: Update `apps/web` imports**

Replace direct imports of moved files with `@florin/core/lib/...` imports. Add `@florin/core` as a workspace dependency in `apps/web/package.json`:

```json
{
  "dependencies": {
    "@florin/core": "workspace:*"
  }
}
```

Keep a backwards-compatible `apps/web/src/lib/format/currency.ts` that creates the `fr-FR`/`EUR` instance and re-exports `formatCurrency` / `formatCurrencySigned` so existing page imports don't break:

```typescript
import { createCurrencyFormatter } from '@florin/core/lib/format'
const { format, formatSigned } = createCurrencyFormatter('fr-FR', 'EUR')
export const formatCurrency = format
export const formatCurrencySigned = formatSigned
```

- [ ] **Step 4: Run build + tests**

Run: `pnpm turbo build`
Run: `pnpm turbo test`
Expected: Everything passes. `apps/web` resolves `@florin/core` via workspace protocol.

- [ ] **Step 5: Commit**

```bash
git add packages/core/ apps/web/
git commit -m "refactor(core): extract shared lib code (format, categorization, loan, utils) to @florin/core"
```

---

### Task 4: Create `@florin/db-pg` — extract PostgreSQL schema + queries

**Files:**
- Create: `packages/db-pg/package.json`
- Create: `packages/db-pg/tsconfig.json`
- Create: `packages/db-pg/src/schema.ts` (move from `apps/web/src/db/schema.ts`)
- Create: `packages/db-pg/src/client.ts` (move from `apps/web/src/db/client.ts`)
- Create: `packages/db-pg/src/queries/dashboard.ts`
- Create: `packages/db-pg/src/queries/reflect.ts`
- Create: `packages/db-pg/src/queries/loan-liabilities.ts`
- Create: `packages/db-pg/src/queries/index.ts` (factory that returns FlorinQueries)
- Create: `packages/db-pg/src/actions/index.ts` (factory that returns FlorinMutations)
- Create: `packages/db-pg/src/index.ts`
- Move: `apps/web/drizzle/` → `packages/db-pg/drizzle/` (migrations)
- Modify: `apps/web/package.json` (add `@florin/db-pg` dep, remove drizzle/postgres deps)
- Modify: `apps/web/src/db/` (thin re-exports from `@florin/db-pg`)

- [ ] **Step 1: Create `packages/db-pg/package.json`**

```json
{
  "name": "@florin/db-pg",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "exports": {
    ".": "./src/index.ts",
    "./schema": "./src/schema.ts"
  },
  "dependencies": {
    "@florin/core": "workspace:*",
    "drizzle-orm": "^0.45.2",
    "postgres": "^3.4.9"
  },
  "devDependencies": {
    "drizzle-kit": "^0.31.10",
    "typescript": "^6.0.2"
  }
}
```

- [ ] **Step 2: Move schema, client, queries, actions**

Move the existing files to `packages/db-pg/src/`. The schema stays as-is (pgTable, pgEnum). The queries and actions implementations are moved but their public return types are replaced with the `@florin/core` interfaces.

Each query file keeps its SQL exactly as-is — the whole point is that PG queries stay PG.

Create `packages/db-pg/src/queries/index.ts`:

```typescript
import type { FlorinQueries } from '@florin/core/types'
import type { DB } from '../client'
import { getNetWorth, getMonthBurn, getAvgMonthlyBurn, getPatrimonyTimeSeries, getMonthByCategory, getTopExpenses, countUncategorizedExpensesThisMonth, getDataSourceInfo } from './dashboard'
import { getMonthlyFlows, getCategoryBreakdown, getAgeOfMoney, getNetWorthSeries } from './reflect'
// ... import all query functions

export function createPgQueries(db: DB): FlorinQueries {
  return {
    getNetWorth: () => getNetWorth(db),
    getMonthBurn: (opts) => getMonthBurn(db, opts),
    getAvgMonthlyBurn: (months) => getAvgMonthlyBurn(db, months),
    getPatrimonyTimeSeries: (months) => getPatrimonyTimeSeries(db, months),
    getMonthByCategory: () => getMonthByCategory(db),
    getTopExpenses: (n, days, catId) => getTopExpenses(db, n, days, catId),
    countUncategorizedExpensesThisMonth: () => countUncategorizedExpensesThisMonth(db),
    getDataSourceInfo: () => getDataSourceInfo(db),
    getMonthlyFlows: (months) => getMonthlyFlows(db, months),
    getCategoryBreakdown: (days) => getCategoryBreakdown(db, days),
    getAgeOfMoney: (days) => getAgeOfMoney(db, days),
    getNetWorthSeries: (months) => getNetWorthSeries(db, months),
    // ... remaining query bindings
  }
}
```

Each query function is refactored to accept `db` as a first parameter instead of importing the global singleton. For example `getNetWorth()` becomes `getNetWorth(db: DB)`.

- [ ] **Step 3: Wire `apps/web` to use `@florin/db-pg`**

Add `@florin/db-pg` as a dependency. Replace `apps/web/src/db/client.ts` with a thin wrapper:

```typescript
import { createPgClient } from '@florin/db-pg'
import { env } from '@/server/env'

export const { db, queries, actions } = createPgClient(env.DATABASE_URL)
```

Update page imports: replace `import { getNetWorth } from '@/server/queries/dashboard'` with `import { queries } from '@/db/client'` then call `queries.getNetWorth()`.

The server actions in `apps/web/src/server/actions/` stay in `apps/web` (not moved to db-pg) because they call `revalidatePath` which is Next.js-specific. They import mutations from `@florin/db-pg` and wrap with cache invalidation.

- [ ] **Step 4: Move migrations**

Move `apps/web/drizzle/` to `packages/db-pg/drizzle/`. Update `drizzle.config.ts` path references.

- [ ] **Step 5: Verify web app still works**

Run: `pnpm turbo build`
Run: `cd apps/web && pnpm dev` — verify dashboard loads with real data.
Run: `pnpm turbo test`

- [ ] **Step 6: Commit**

```bash
git add packages/db-pg/ apps/web/
git commit -m "refactor(db-pg): extract PostgreSQL schema, queries, and actions to @florin/db-pg"
```

---

### Task 5: Create `@florin/db-sqlite` — SQLite schema + queries

**Files:**
- Create: `packages/db-sqlite/package.json`
- Create: `packages/db-sqlite/tsconfig.json`
- Create: `packages/db-sqlite/src/schema.ts` (SQLite equivalent of PG schema)
- Create: `packages/db-sqlite/src/client.ts`
- Create: `packages/db-sqlite/src/queries/dashboard.ts`
- Create: `packages/db-sqlite/src/queries/reflect.ts`
- Create: `packages/db-sqlite/src/queries/loan-liabilities.ts`
- Create: `packages/db-sqlite/src/queries/index.ts`
- Create: `packages/db-sqlite/src/actions/index.ts`
- Create: `packages/db-sqlite/src/index.ts`
- Create: `packages/db-sqlite/drizzle.config.ts`
- Test: `packages/db-sqlite/src/__tests__/queries.test.ts`

- [ ] **Step 1: Create SQLite schema**

Translate `@florin/db-pg/src/schema.ts` to SQLite dialect:

```typescript
import { sql } from 'drizzle-orm'
import { index, integer, real, sqliteTable, text, uniqueIndex } from 'drizzle-orm/sqlite-core'
import { randomUUID } from 'node:crypto'

const uuid = () => text().primaryKey().$defaultFn(() => randomUUID())
const timestamp = () => text() // ISO 8601 strings
const numeric = () => real()
const boolean = () => integer({ mode: 'boolean' })

export const users = sqliteTable('users', {
  id: uuid(),
  email: text('email').notNull().unique(),
  passwordHash: text('password_hash').notNull(),
  locale: text('locale').notNull().default('en'),
  baseCurrency: text('base_currency').notNull().default('EUR'),
  createdAt: timestamp().notNull().default(sql`(datetime('now'))`),
  updatedAt: timestamp().notNull().default(sql`(datetime('now'))`),
})

// ... same pattern for all other tables, replacing:
//   pgEnum → omit (just use text)
//   pgTable → sqliteTable
//   uuid().defaultRandom() → uuid() helper above
//   timestamp({ withTimezone: true }) → timestamp() helper above
//   numeric(14, 2) → numeric() helper above (real)
//   boolean → boolean() helper above (integer 0/1)
```

Also add the desktop-only `settings` table:

```typescript
export const settings = sqliteTable('settings', {
  key: text('key').primaryKey(),
  value: text('value').notNull(),
})
```

- [ ] **Step 2: Create SQLite client factory**

```typescript
import Database from 'better-sqlite3'
import { drizzle } from 'drizzle-orm/better-sqlite3'
import * as schema from './schema'

export function createSqliteClient(dbPath: string) {
  const sqlite = new Database(dbPath)
  sqlite.pragma('journal_mode = WAL')
  sqlite.pragma('foreign_keys = ON')
  const db = drizzle(sqlite, { schema })
  return { db, sqlite }
}

export type SqliteDB = ReturnType<typeof createSqliteClient>['db']
```

- [ ] **Step 3: Implement SQLite queries**

Port each query from `@florin/db-pg`, replacing PG-specific SQL:

- `to_char(ts, 'YYYY-MM-DD')` → `strftime('%Y-%m-%d', ts)`
- `to_char(ts, 'YYYY-MM')` → `strftime('%Y-%m', ts)`
- Remove `::uuid`, `::integer` casts
- `COALESCE(SUM(...), 0)::text` → `COALESCE(SUM(...), 0)`
- `ilike(col, pattern)` → `sql\`${col} LIKE ${pattern} COLLATE NOCASE\``

The query implementations are separate files that mirror the PG structure but with SQLite-compatible SQL.

Create `packages/db-sqlite/src/queries/index.ts` with the same `createSqliteQueries(db)` factory pattern.

- [ ] **Step 4: Implement SQLite actions (mutations)**

Same factory pattern: `createSqliteMutations(db)` returning `FlorinMutations`. Notable differences:
- `reorderAccounts`: remove `::uuid` and `::integer` casts from the CASE expression
- `recomputeAccountBalance`: remove `::text` cast
- `mergeAccount`: use `db.transaction()` (supported by better-sqlite3)

- [ ] **Step 5: Write tests**

Create `packages/db-sqlite/src/__tests__/queries.test.ts`:

```typescript
import { describe, it, expect, beforeEach } from 'vitest'
import { createSqliteClient } from '../client'
import { createSqliteQueries } from '../queries'
import { createSqliteMutations } from '../actions'
import { migrate } from 'drizzle-orm/better-sqlite3/migrator'

describe('SQLite queries', () => {
  let queries: ReturnType<typeof createSqliteQueries>
  let mutations: ReturnType<typeof createSqliteMutations>

  beforeEach(() => {
    const { db } = createSqliteClient(':memory:')
    migrate(db, { migrationsFolder: './drizzle' })
    queries = createSqliteQueries(db)
    mutations = createSqliteMutations(db)
  })

  it('getNetWorth returns zeros on empty db', async () => {
    const nw = await queries.getNetWorth()
    expect(nw).toEqual({ gross: 0, liability: 0, net: 0 })
  })

  it('createAccount + listAccounts round-trips', async () => {
    const result = await mutations.createAccount({
      name: 'Checking',
      kind: 'checking',
      currentBalance: 1000,
    })
    expect(result.success).toBe(true)
    const accounts = await queries.listAccounts()
    expect(accounts).toHaveLength(1)
    expect(accounts[0]!.name).toBe('Checking')
  })

  it('addTransaction updates account balance', async () => {
    const acct = await mutations.createAccount({
      name: 'Test', kind: 'checking', currentBalance: 0,
    })
    await mutations.addTransaction({
      accountId: acct.data!.id,
      occurredAt: new Date(),
      amount: -50,
      payee: 'Shop',
    })
    const accounts = await queries.listAccounts()
    expect(Number(accounts[0]!.currentBalance)).toBe(-50)
  })

  it('getMonthBurn calculates burn correctly', async () => {
    const acct = await mutations.createAccount({
      name: 'Test', kind: 'checking', currentBalance: 0,
    })
    await mutations.addTransaction({
      accountId: acct.data!.id,
      occurredAt: new Date(),
      amount: -100,
      payee: 'Rent',
    })
    const burn = await queries.getMonthBurn()
    expect(burn).toBe(100)
  })
})
```

- [ ] **Step 6: Run tests**

Run: `cd packages/db-sqlite && pnpm test`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add packages/db-sqlite/
git commit -m "feat(db-sqlite): add SQLite schema, queries, actions, and tests for desktop app"
```

---

### Task 6: Add i18n to `@florin/core`

**Files:**
- Create: `packages/core/src/i18n/en.json`
- Create: `packages/core/src/i18n/fr.json`
- Create: `packages/core/src/i18n/index.ts`
- Create: `packages/core/src/i18n/seed-categories.ts`

- [ ] **Step 1: Create English translations**

`packages/core/src/i18n/en.json` — flat key-value. Cover all UI strings, category seeds, onboarding text:

```json
{
  "app.name": "Florin",
  "app.tagline": "Your finances, your machine.",

  "nav.dashboard": "Dashboard",
  "nav.transactions": "Transactions",
  "nav.accounts": "Accounts",
  "nav.categories": "Categories",
  "nav.review": "Review",
  "nav.reflect": "Reflect",
  "nav.settings": "Settings",
  "nav.tools": "Tools",

  "kpi.netWorth": "Net Worth",
  "kpi.burnRate": "Burn Rate",
  "kpi.safetyGauge": "Safety Gauge",
  "kpi.budgetRemaining": "Budget Remaining",

  "dashboard.patrimony": "Patrimony",
  "dashboard.incomeVsSpending": "Income vs Spending",
  "dashboard.topExpenses": "Top Expenses",
  "dashboard.byCategory": "This Month by Category",
  "dashboard.syncAll": "Sync All",
  "dashboard.lastSync": "Last sync",

  "transactions.add": "Add Transaction",
  "transactions.filters": "Filters",
  "transactions.noResults": "No transactions found",

  "accounts.addAccount": "Add Account",
  "accounts.bankConnections": "Bank Connections",
  "accounts.connectBank": "Connect Bank",

  "categories.income": "Income",
  "categories.bills": "Bills",
  "categories.needs": "Needs",
  "categories.wants": "Wants",
  "categories.savings": "Savings",

  "review.approve": "Approve",
  "review.approveAll": "Approve All",

  "onboarding.welcome.title": "Welcome to Florin",
  "onboarding.welcome.subtitle": "Your finances, your machine. All data stays on this computer.",
  "onboarding.locale.title": "Language & Currency",
  "onboarding.locale.subtitle": "Choose your language and base currency.",
  "onboarding.banking.title": "Bank Sync (Optional)",
  "onboarding.banking.subtitle": "Connect your bank via PSD2 for automatic transaction sync.",
  "onboarding.banking.skip": "Skip for now",
  "onboarding.banking.setup": "Set up Enable Banking",
  "onboarding.categories.title": "Your Categories",
  "onboarding.categories.subtitle": "Review and customize your spending categories.",
  "onboarding.account.title": "First Account",
  "onboarding.account.subtitle": "Create your first account to start tracking.",
  "onboarding.tutorial.title": "Quick Tour",
  "onboarding.tutorial.subtitle": "Let us show you around.",

  "tray.syncNow": "Sync Now",
  "tray.addTransaction": "Add Transaction",
  "tray.openDashboard": "Open Dashboard",
  "tray.quit": "Quit",
  "tray.recent": "Recent",
  "tray.updateAvailable": "Update available"
}
```

- [ ] **Step 2: Create French translations**

`packages/core/src/i18n/fr.json` — same keys, French values. Category seeds match the current seed.ts.

- [ ] **Step 3: Create i18n helper**

```typescript
import en from './en.json'
import fr from './fr.json'

const translations: Record<string, Record<string, string>> = { en, fr }

export function createT(locale: string) {
  const lang = locale.startsWith('fr') ? 'fr' : 'en'
  const dict = translations[lang] ?? translations.en!
  return function t(key: string, fallback?: string): string {
    return dict[key] ?? fallback ?? key
  }
}

export type TFunction = ReturnType<typeof createT>
```

- [ ] **Step 4: Create locale-aware category seeds**

`packages/core/src/i18n/seed-categories.ts`:

```typescript
export interface SeedCategory {
  name: string
  emoji: string
  isFixed?: boolean
}

export interface SeedCategoryGroup {
  name: string
  kind: 'income' | 'expense'
  color: string
  categories: SeedCategory[]
}

export function getSeedCategories(locale: string): SeedCategoryGroup[] {
  const fr = locale.startsWith('fr')
  return [
    {
      name: fr ? 'Revenus' : 'Income',
      kind: 'income',
      color: '#22c55e',
      categories: [
        { name: fr ? 'Salaires' : 'Wages', emoji: '💸' },
        { name: fr ? 'Gains additionnels' : 'Side Income', emoji: '↩️' },
        { name: 'Ready to Assign', emoji: '🪙' },
      ],
    },
    {
      name: fr ? 'Factures' : 'Bills',
      kind: 'expense',
      color: '#3b82f6',
      categories: [
        { name: fr ? 'Loyer' : 'Rent', emoji: '🏠', isFixed: true },
        { name: fr ? 'Assurances' : 'Insurance', emoji: '📄', isFixed: true },
        { name: fr ? 'Abonnements' : 'Subscriptions', emoji: '🔄', isFixed: true },
      ],
    },
    {
      name: fr ? 'Besoins' : 'Needs',
      kind: 'expense',
      color: '#06b6d4',
      categories: [
        { name: fr ? 'Courses' : 'Groceries', emoji: '🛒' },
        { name: 'Transports', emoji: '🚈' },
      ],
    },
    {
      name: fr ? 'Envies' : 'Wants',
      kind: 'expense',
      color: '#f59e0b',
      categories: [
        { name: fr ? 'Sorties & Restos' : 'Dining Out', emoji: '🍿' },
        { name: fr ? 'Voyages' : 'Travel', emoji: '🏝️' },
        { name: fr ? 'Cadeaux' : 'Gifts', emoji: '🎁' },
        { name: fr ? 'Vêtements' : 'Clothes', emoji: '🧢' },
        { name: fr ? 'Autres' : 'Other', emoji: '⚠️' },
      ],
    },
    {
      name: fr ? 'Épargne' : 'Savings',
      kind: 'expense',
      color: '#a855f7',
      categories: [
        { name: fr ? 'Épargne' : 'Savings', emoji: '💶' },
      ],
    },
  ]
}
```

- [ ] **Step 5: Update `packages/core/package.json` exports**

Add `"./i18n": "./src/i18n/index.ts"` and `"./i18n/seed-categories": "./src/i18n/seed-categories.ts"`.

- [ ] **Step 6: Commit**

```bash
git add packages/core/src/i18n/
git commit -m "feat(core): add i18n framework with EN/FR translations and locale-aware category seeds"
```

---

### Task 7: Extract UI components to `@florin/core`

**Files:**
- Move: `apps/web/src/components/dashboard/` → `packages/core/src/components/dashboard/`
- Move: `apps/web/src/components/transactions/` → `packages/core/src/components/transactions/`
- Move: `apps/web/src/components/accounts/` → `packages/core/src/components/accounts/`
- Move: `apps/web/src/components/categories/` → `packages/core/src/components/categories/`
- Move: `apps/web/src/components/review/` → `packages/core/src/components/review/`
- Move: `apps/web/src/components/reflect/` → `packages/core/src/components/reflect/`
- Move: `apps/web/src/components/shell/` → `packages/core/src/components/shell/`
- Move: `apps/web/src/components/theme/` → `packages/core/src/components/theme/`
- Move: `apps/web/src/components/ui/` → `packages/core/src/components/ui/`
- Modify: `packages/core/package.json` (add React, UI deps, component exports)
- Modify: `apps/web/` (replace component imports with `@florin/core` imports)

- [ ] **Step 1: Add UI dependencies to `@florin/core`**

Add to `packages/core/package.json` dependencies:
```json
{
  "react": "^19.2.4",
  "react-dom": "^19.2.4",
  "recharts": "^3.8.1",
  "@base-ui/react": "^1.3.0",
  "@dnd-kit/core": "^6.3.1",
  "@dnd-kit/sortable": "^10.0.0",
  "lucide-react": "^1.7.0",
  "class-variance-authority": "^0.7.1",
  "clsx": "^2.1.1",
  "tailwind-merge": "^3.5.0",
  "sonner": "^2.0.7",
  "react-hook-form": "^7.72.1",
  "@hookform/resolvers": "^5.2.2"
}
```

Add component exports:
```json
{
  "exports": {
    "./components/*": "./src/components/*"
  }
}
```

- [ ] **Step 2: Move all component directories to core**

Move each directory. The components are already "pure" React — they accept data as props and call server actions passed as props. The main refactor needed:

- Replace `@/lib/format/currency` imports with `@florin/core/lib/format`
- Replace `@/lib/utils` imports with `@florin/core/lib/utils`
- Server actions are NOT moved (they're app-specific due to `revalidatePath`). Components receive action functions as props.

For components that currently import server actions directly (e.g. `add-transaction-modal.tsx` imports `addTransaction`), refactor to accept the action as a prop:

```typescript
// Before (in apps/web)
import { addTransaction } from '@/server/actions/transactions'

// After (in @florin/core)
interface AddTransactionModalProps {
  onAdd: (input: AddTransactionInput) => Promise<ActionResult<{ id: string }>>
  // ... other props
}
```

- [ ] **Step 3: Update `apps/web` page files**

Each page now imports components from `@florin/core` and passes server actions as props:

```typescript
import { NetWorthCard } from '@florin/core/components/dashboard/net-worth-card'
import { addTransaction } from '@/server/actions/transactions'
// ...pass addTransaction as prop to the component
```

- [ ] **Step 4: Verify web app still works**

Run: `pnpm turbo build`
Run: `cd apps/web && pnpm dev`
Expected: Dashboard renders identically. All features work.

- [ ] **Step 5: Commit**

```bash
git add packages/core/src/components/ apps/web/
git commit -m "refactor(core): extract all UI components to @florin/core, pass server actions as props"
```

---

## Phase 2: Electron Shell + Desktop App

### Task 8: Scaffold `apps/desktop` Electron app

**Files:**
- Create: `apps/desktop/package.json`
- Create: `apps/desktop/tsconfig.json`
- Create: `apps/desktop/main/index.ts` (Electron main process)
- Create: `apps/desktop/main/window.ts` (BrowserWindow management)
- Create: `apps/desktop/electron-builder.yml`
- Create: `apps/desktop/src/` (Next.js app — copy structure from apps/web, rewire to use @florin/db-sqlite)

- [ ] **Step 1: Create `apps/desktop/package.json`**

```json
{
  "name": "@florin/desktop",
  "version": "0.1.0",
  "private": true,
  "main": "main/index.ts",
  "scripts": {
    "dev": "electron .",
    "build": "next build && electron-builder",
    "start": "electron ."
  },
  "dependencies": {
    "@florin/core": "workspace:*",
    "@florin/db-sqlite": "workspace:*",
    "better-sqlite3": "^11.0.0",
    "electron-updater": "^6.3.0",
    "next": "^15.5.14",
    "react": "^19.2.4",
    "react-dom": "^19.2.4"
  },
  "devDependencies": {
    "electron": "^35.0.0",
    "electron-builder": "^25.0.0",
    "typescript": "^6.0.2"
  }
}
```

- [ ] **Step 2: Create Electron main process**

`apps/desktop/main/index.ts`:

```typescript
import { app, BrowserWindow } from 'electron'
import path from 'node:path'
import { createSqliteClient } from '@florin/db-sqlite'
import { createWindow, getMainWindow } from './window'
import { setupTray } from './tray'

const DB_PATH = path.join(app.getPath('userData'), 'florin.db')

let dbClient: ReturnType<typeof createSqliteClient>

app.whenReady().then(async () => {
  // Initialize SQLite
  dbClient = createSqliteClient(DB_PATH)

  // Run migrations
  const { migrate } = await import('drizzle-orm/better-sqlite3/migrator')
  migrate(dbClient.db, { migrationsFolder: path.join(__dirname, '../drizzle') })

  // Start Next.js custom server
  const port = await startNextServer()

  // Create main window
  createWindow(port)

  // Set up tray
  setupTray(port)
})

app.on('window-all-closed', () => {
  // Don't quit — keep running in tray
})

app.on('before-quit', () => {
  dbClient?.sqlite.close()
})

async function startNextServer(): Promise<number> {
  const next = (await import('next')).default
  const nextApp = next({ dev: false, dir: path.join(__dirname, '..') })
  const handle = nextApp.getRequestHandler()
  await nextApp.prepare()

  const { createServer } = await import('node:http')
  return new Promise((resolve) => {
    const server = createServer((req, res) => handle(req, res))
    server.listen(0, '127.0.0.1', () => {
      const addr = server.address()
      const port = typeof addr === 'object' ? addr!.port : 3001
      resolve(port)
    })
  })
}
```

- [ ] **Step 3: Create window manager**

`apps/desktop/main/window.ts`:

```typescript
import { BrowserWindow, app } from 'electron'

let mainWindow: BrowserWindow | null = null

export function createWindow(port: number) {
  mainWindow = new BrowserWindow({
    width: 1280,
    height: 800,
    titleBarStyle: 'hiddenInset',
    trafficLightPosition: { x: 16, y: 16 },
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
    },
  })

  mainWindow.loadURL(`http://127.0.0.1:${port}`)

  mainWindow.on('close', (event) => {
    // Hide instead of close — app stays in tray
    if (!app.isQuitting) {
      event.preventDefault()
      mainWindow?.hide()
    }
  })
}

export function getMainWindow() {
  return mainWindow
}

export function showMainWindow() {
  if (mainWindow) {
    mainWindow.show()
    mainWindow.focus()
  }
}
```

- [ ] **Step 4: Create `electron-builder.yml`**

```yaml
appId: com.florin.desktop
productName: Florin
mac:
  category: public.app-category.finance
  icon: assets/icon.icns
  target:
    - target: dmg
      arch:
        - universal
dmg:
  title: Florin
  artifactName: Florin-${version}-${arch}.dmg
publish:
  provider: github
  owner: adrbn
  repo: florin
```

- [ ] **Step 5: Verify Electron launches**

Run: `cd apps/desktop && pnpm dev`
Expected: Electron window opens showing the Next.js app (may need placeholder pages initially).

- [ ] **Step 6: Commit**

```bash
git add apps/desktop/
git commit -m "feat(desktop): scaffold Electron app with main process, window management, and builder config"
```

---

### Task 9: Build tray widget (HTML popup)

**Files:**
- Create: `apps/desktop/main/tray.ts`
- Create: `apps/desktop/tray-ui/index.html`
- Create: `apps/desktop/tray-ui/tray.css`
- Create: `apps/desktop/tray-ui/tray.js`
- Create: `apps/desktop/main/ipc.ts` (IPC handlers for tray data)
- Create: `apps/desktop/assets/tray-icon.png` (16x16 + 32x32 template icon)

- [ ] **Step 1: Create IPC handlers**

`apps/desktop/main/ipc.ts` — exposes query data to the tray widget via IPC:

```typescript
import { ipcMain } from 'electron'
import type { FlorinQueries } from '@florin/core/types'

export function registerIpcHandlers(queries: FlorinQueries) {
  ipcMain.handle('tray:get-data', async () => {
    const [netWorth, burn, topExpenses, reviewCount] = await Promise.all([
      queries.getNetWorth(),
      queries.getMonthBurn(),
      queries.getTopExpenses(3, 7),
      queries.countNeedsReview(),
    ])
    return { netWorth, burn, topExpenses, reviewCount }
  })

  ipcMain.handle('tray:sync-all', async () => {
    // Delegate to sync module — implemented in Task 10
    return { success: true }
  })
}
```

- [ ] **Step 2: Create tray module**

`apps/desktop/main/tray.ts`:

```typescript
import { Tray, BrowserWindow, nativeImage, screen } from 'electron'
import path from 'node:path'
import { showMainWindow } from './window'

let tray: Tray | null = null
let trayWindow: BrowserWindow | null = null

export function setupTray(port: number) {
  const iconPath = path.join(__dirname, '../assets/tray-iconTemplate.png')
  const icon = nativeImage.createFromPath(iconPath)
  tray = new Tray(icon)
  tray.setToolTip('Florin')

  trayWindow = new BrowserWindow({
    width: 320,
    height: 420,
    show: false,
    frame: false,
    resizable: false,
    movable: false,
    alwaysOnTop: true,
    skipTaskbar: true,
    transparent: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  })

  trayWindow.loadFile(path.join(__dirname, '../tray-ui/index.html'))

  tray.on('click', () => {
    if (trayWindow?.isVisible()) {
      trayWindow.hide()
    } else {
      positionTrayWindow()
      trayWindow?.show()
      trayWindow?.webContents.send('tray:refresh')
    }
  })
}

function positionTrayWindow() {
  if (!tray || !trayWindow) return
  const trayBounds = tray.getBounds()
  const windowBounds = trayWindow.getBounds()
  const x = Math.round(trayBounds.x + trayBounds.width / 2 - windowBounds.width / 2)
  const y = Math.round(trayBounds.y + trayBounds.height)
  trayWindow.setPosition(x, y, false)
}
```

- [ ] **Step 3: Create tray UI HTML**

`apps/desktop/tray-ui/index.html` — the rich dashboard popup (design B from brainstorming). Dark theme, 320px, shows net worth with sparkline, burn rate, budget remaining, recent transactions with category dots, quick actions.

This is a standalone HTML file (not React) — it communicates with the main process via the preload script's exposed `window.florin.getTrayData()` and `window.florin.onRefresh(callback)`.

- [ ] **Step 4: Create preload script**

`apps/desktop/main/preload.ts`:

```typescript
import { contextBridge, ipcRenderer } from 'electron'

contextBridge.exposeInMainWorld('florin', {
  getTrayData: () => ipcRenderer.invoke('tray:get-data'),
  syncAll: () => ipcRenderer.invoke('tray:sync-all'),
  openDashboard: () => ipcRenderer.send('open-dashboard'),
  openAddTransaction: () => ipcRenderer.send('open-add-transaction'),
  onRefresh: (cb: () => void) => ipcRenderer.on('tray:refresh', cb),
})
```

- [ ] **Step 5: Verify tray works**

Run: `cd apps/desktop && pnpm dev`
Expected: Tray icon appears in macOS menu bar. Clicking opens the HTML popup.

- [ ] **Step 6: Commit**

```bash
git add apps/desktop/main/tray.ts apps/desktop/main/ipc.ts apps/desktop/main/preload.ts apps/desktop/tray-ui/
git commit -m "feat(desktop): add menu bar tray widget with HTML popup dashboard"
```

---

### Task 10: Wire desktop Next.js pages to `@florin/db-sqlite`

**Files:**
- Create: `apps/desktop/src/app/` (copy page structure from `apps/web/src/app/`)
- Create: `apps/desktop/src/db/client.ts` (SQLite client)
- Create: `apps/desktop/src/server/actions/` (server actions wrapping @florin/db-sqlite mutations)
- Modify: All page.tsx files to import from `@florin/core` components + local db client

- [ ] **Step 1: Create desktop db client**

```typescript
import { createSqliteClient } from '@florin/db-sqlite'
import { createSqliteQueries } from '@florin/db-sqlite'
import { createSqliteMutations } from '@florin/db-sqlite'
import { app } from 'electron'
import path from 'node:path'

const DB_PATH = path.join(app.getPath('userData'), 'florin.db')
const { db } = createSqliteClient(DB_PATH)
export const queries = createSqliteQueries(db)
export const mutations = createSqliteMutations(db)
```

- [ ] **Step 2: Create desktop server actions**

Each action file in `apps/desktop/src/server/actions/` wraps the mutation with `revalidatePath`:

```typescript
'use server'
import { revalidatePath } from 'next/cache'
import { mutations } from '@/db/client'
import type { CreateAccountInput } from '@florin/core/types'

export async function createAccount(input: CreateAccountInput) {
  const result = await mutations.createAccount(input)
  revalidatePath('/accounts')
  revalidatePath('/')
  return result
}
// ... same pattern for all actions
```

- [ ] **Step 3: Create desktop pages**

Copy page structure from `apps/web/src/app/(dashboard)/`. Each page:
- Imports components from `@florin/core`
- Calls `queries.*` from `apps/desktop/src/db/client`
- Passes data to shared components

Example `apps/desktop/src/app/(dashboard)/page.tsx`:

```typescript
import { queries } from '@/db/client'
import { NetWorthCard } from '@florin/core/components/dashboard/net-worth-card'
import { BurnRateCard } from '@florin/core/components/dashboard/burn-rate-card'
// ... etc

export const dynamic = 'force-dynamic'

export default async function DashboardPage() {
  const [netWorth, burn, avgBurn, patrimony, byCategory, topExpenses] = await Promise.all([
    queries.getNetWorth(),
    queries.getMonthBurn(),
    queries.getAvgMonthlyBurn(),
    queries.getPatrimonyTimeSeries(),
    queries.getMonthByCategory(),
    queries.getTopExpenses(),
  ])

  return (
    // Same JSX as web, using shared components
  )
}
```

- [ ] **Step 4: Remove web-only features from desktop**

- No login page (skip auth)
- No legacy XLSX import
- No Docker/deploy config
- Remove `xlsx` dependency

- [ ] **Step 5: Verify desktop app renders**

Run: `cd apps/desktop && pnpm dev`
Expected: Electron window shows dashboard with empty state (no data yet).

- [ ] **Step 6: Commit**

```bash
git add apps/desktop/src/
git commit -m "feat(desktop): wire Next.js pages to SQLite via @florin/db-sqlite"
```

---

### Task 11: Enable Banking in desktop

**Files:**
- Move: `apps/web/src/server/banking/` shared modules to `packages/core/src/banking/`
- Create: `apps/desktop/src/server/banking/` (desktop-specific wiring)
- Create: `apps/desktop/main/scheduler.ts` (sync scheduler in main process)

- [ ] **Step 1: Extract banking client to core**

Move these to `@florin/core`:
- `enable-banking.ts` (the REST client — JWT signing, API calls)
- `sync.ts` (sync logic)
- `sync-all.ts`
- `types.ts`
- `state.ts`

These are DB-agnostic — they take a mutation interface and call it. Refactor to accept `FlorinMutations` + config instead of importing the global db.

- [ ] **Step 2: Desktop banking config**

Instead of env vars, read EB credentials from SQLite `settings` table:

```typescript
import { queries } from '@/db/client'

export async function getEnableBankingConfig() {
  const settings = await queries.getSettings(['eb_app_id', 'eb_key_path'])
  if (!settings.eb_app_id || !settings.eb_key_path) return null
  return {
    appId: settings.eb_app_id,
    privateKeyPath: settings.eb_key_path,
  }
}
```

- [ ] **Step 3: Sync scheduler in Electron main process**

`apps/desktop/main/scheduler.ts`:

```typescript
import { syncAllConnections } from '@florin/core/banking/sync-all'

let intervalId: NodeJS.Timeout | null = null

export function startSyncScheduler(config: { queries: FlorinQueries; mutations: FlorinMutations }) {
  // Initial sync after 2-minute warmup
  setTimeout(() => {
    syncAllConnections(config.queries, config.mutations)
  }, 2 * 60 * 1000)

  // Then every 6 hours
  intervalId = setInterval(() => {
    syncAllConnections(config.queries, config.mutations)
  }, 6 * 60 * 60 * 1000)
}

export function stopSyncScheduler() {
  if (intervalId) clearInterval(intervalId)
}
```

- [ ] **Step 4: Tray sync status**

Update tray IPC to expose sync status (syncing/synced/error) and trigger from the tray "Sync Now" button.

- [ ] **Step 5: Commit**

```bash
git add packages/core/src/banking/ apps/desktop/main/scheduler.ts apps/desktop/src/server/banking/
git commit -m "feat(desktop): enable banking integration with SQLite config and background sync scheduler"
```

---

## Phase 3: Onboarding, Tutorial, i18n, PIN Auth

### Task 12: Onboarding wizard

**Files:**
- Create: `packages/core/src/components/onboarding/wizard.tsx`
- Create: `packages/core/src/components/onboarding/steps/welcome.tsx`
- Create: `packages/core/src/components/onboarding/steps/locale-picker.tsx`
- Create: `packages/core/src/components/onboarding/steps/banking-setup.tsx`
- Create: `packages/core/src/components/onboarding/steps/category-preview.tsx`
- Create: `packages/core/src/components/onboarding/steps/first-account.tsx`
- Create: `packages/core/src/components/onboarding/steps/tutorial.tsx`
- Create: `apps/desktop/src/app/(dashboard)/onboarding/page.tsx`

- [ ] **Step 1: Build wizard shell**

Multi-step wizard component with progress indicator, back/next navigation, step validation.

- [ ] **Step 2: Implement each step**

1. **Welcome** — title, subtitle, illustration, "Get Started" button
2. **Locale & Currency** — dropdown for language (EN/FR), dropdown for currency (EUR/GBP/USD/CHF). Saves to SQLite settings.
3. **Banking Setup** — explains Enable Banking, link to registration page, file picker for RSA key, text field for App ID. "Skip for now" button. Saves to SQLite settings.
4. **Category Preview** — renders `getSeedCategories(locale)` in an editable list. User can rename, delete, add, reorder. "Confirm" seeds the DB.
5. **First Account** — if EB configured, shows "Connect Bank" button (starts PSD2 flow). Otherwise shows manual account form (name, type, balance).
6. **Tutorial** — tooltip-driven walkthrough (implemented in Task 12).

- [ ] **Step 3: Auto-redirect to onboarding**

In the desktop dashboard layout, check if DB has any accounts/transactions. If empty, redirect to `/onboarding`.

- [ ] **Step 4: Commit**

```bash
git add packages/core/src/components/onboarding/ apps/desktop/src/app/
git commit -m "feat(desktop): add 6-step onboarding wizard with locale, banking, and category setup"
```

---

### Task 13: Interactive tutorial

**Files:**
- Create: `packages/core/src/components/tutorial/tutorial-overlay.tsx`
- Create: `packages/core/src/components/tutorial/tutorial-steps.ts`

- [ ] **Step 1: Build tooltip overlay system**

A lightweight tooltip overlay that highlights UI elements and shows explanatory text. Steps:

1. "This is your net worth — the total value of all your accounts"
2. "Your burn rate shows how much you spend per month"
3. "Click here to add a transaction manually"
4. "The sidebar lets you navigate between sections"
5. "Use the menu bar icon for quick access anytime"

Each step targets a CSS selector, positions a tooltip, and highlights the element.

- [ ] **Step 2: Hook into onboarding final step**

After the wizard completes, launch the tutorial. Also accessible from Settings > "Replay Tutorial".

- [ ] **Step 3: Commit**

```bash
git add packages/core/src/components/tutorial/
git commit -m "feat(desktop): add interactive tutorial overlay with dismissable tooltip walkthrough"
```

---

### Task 14: Optional PIN auth

**Files:**
- Create: `apps/desktop/src/app/(auth)/pin/page.tsx`
- Create: `apps/desktop/src/components/pin-input.tsx`
- Modify: `apps/desktop/src/middleware.ts`

- [ ] **Step 1: PIN setup in Settings**

Add a "Security" section to Settings page. Toggle "Require PIN on launch". When enabled, prompt for a 4-6 digit PIN, hash with bcrypt, store in SQLite `settings` table as `pin_hash`.

- [ ] **Step 2: PIN entry screen**

Simple PIN input screen shown before the app loads when `pin_hash` exists in settings. Compare with bcrypt. On success, set a session cookie and proceed.

- [ ] **Step 3: Middleware guard**

Desktop middleware checks for the session cookie when PIN is enabled. Redirects to `/pin` if missing.

- [ ] **Step 4: Commit**

```bash
git add apps/desktop/src/app/(auth)/ apps/desktop/src/components/pin-input.tsx apps/desktop/src/middleware.ts
git commit -m "feat(desktop): add optional PIN auth with bcrypt hash stored in SQLite"
```

---

### Task 15: Wire i18n into all components

**Files:**
- Modify: All components in `packages/core/src/components/` to use `t()` instead of hardcoded strings
- Create: `packages/core/src/i18n/context.tsx` (React context provider)

- [ ] **Step 1: Create i18n React context**

```typescript
'use client'
import { createContext, useContext } from 'react'
import { createT, type TFunction } from './index'

const I18nContext = createContext<TFunction>(createT('en'))

export function I18nProvider({ locale, children }: { locale: string; children: React.ReactNode }) {
  const t = createT(locale)
  return <I18nContext.Provider value={t}>{children}</I18nContext.Provider>
}

export function useT() {
  return useContext(I18nContext)
}
```

- [ ] **Step 2: Wrap layouts with I18nProvider**

Both `apps/web` and `apps/desktop` wrap their root layout with `<I18nProvider locale={userLocale}>`.

- [ ] **Step 3: Replace hardcoded strings in components**

Go through each component and replace hardcoded English/French strings with `t('key')` calls.

- [ ] **Step 4: Commit**

```bash
git add packages/core/ apps/web/ apps/desktop/
git commit -m "feat(core): wire i18n context into all shared components"
```

---

## Phase 4: Auto-Update, CI, Packaging

### Task 16: Auto-updater

**Files:**
- Create: `apps/desktop/main/updater.ts`
- Modify: `apps/desktop/main/index.ts` (initialize updater)
- Modify: `apps/desktop/main/tray.ts` (show update notification)

- [ ] **Step 1: Set up electron-updater**

```typescript
import { autoUpdater } from 'electron-updater'
import { BrowserWindow } from 'electron'

export function initAutoUpdater() {
  autoUpdater.autoDownload = true
  autoUpdater.autoInstallOnAppQuit = true

  autoUpdater.on('update-available', (info) => {
    // Notify tray widget
    BrowserWindow.getAllWindows().forEach((w) =>
      w.webContents.send('update-available', info.version)
    )
  })

  autoUpdater.on('update-downloaded', (info) => {
    // Notify tray widget — user can click to restart
    BrowserWindow.getAllWindows().forEach((w) =>
      w.webContents.send('update-downloaded', info.version)
    )
  })

  // Check on launch
  autoUpdater.checkForUpdates()

  // Check every 6 hours
  setInterval(() => autoUpdater.checkForUpdates(), 6 * 60 * 60 * 1000)
}
```

- [ ] **Step 2: Tray update notification**

When `update-downloaded` fires, show a "Restart to update" button in the tray widget.

- [ ] **Step 3: Commit**

```bash
git add apps/desktop/main/updater.ts
git commit -m "feat(desktop): add auto-updater with GitHub Releases and tray notification"
```

---

### Task 17: GitHub Actions CI for desktop builds

**Files:**
- Create: `.github/workflows/desktop-release.yml`

- [ ] **Step 1: Create release workflow**

```yaml
name: Desktop Release

on:
  push:
    tags:
      - 'desktop-v*'

jobs:
  build-mac:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: pnpm
      - run: pnpm install --frozen-lockfile
      - run: pnpm turbo build --filter=@florin/desktop
      - name: Build DMG
        run: cd apps/desktop && pnpm electron-builder --mac
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      - name: Upload to Release
        uses: softprops/action-gh-release@v2
        with:
          files: apps/desktop/dist/*.dmg
```

- [ ] **Step 2: Test workflow locally**

Run: `cd apps/desktop && pnpm electron-builder --mac --dir` (builds without packaging to verify)

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/desktop-release.yml
git commit -m "ci: add GitHub Actions workflow for desktop macOS DMG releases"
```

---

### Task 18: Final integration test

- [ ] **Step 1: Build everything**

Run: `pnpm turbo build`
Expected: All packages and both apps build cleanly.

- [ ] **Step 2: Test web app still works**

Run: `cd apps/web && pnpm dev`
Verify: Dashboard loads, transactions work, Enable Banking flow works.

- [ ] **Step 3: Test desktop app end-to-end**

Run: `cd apps/desktop && pnpm dev`
Verify:
- Electron launches, shows onboarding
- Complete onboarding (locale, skip banking, seed categories, create manual account)
- Dashboard shows the new account
- Add a transaction manually
- Tray widget shows data
- Close window — tray icon persists

- [ ] **Step 4: Build DMG**

Run: `cd apps/desktop && pnpm electron-builder --mac`
Expected: `.dmg` file in `apps/desktop/dist/`.

- [ ] **Step 5: Test DMG install**

Open the `.dmg`, drag Florin to Applications, launch from Applications.
Expected: App launches, shows onboarding, all features work.

- [ ] **Step 6: Commit and tag**

```bash
git add .
git commit -m "feat: Florin Desktop v0.1.0 — Electron macOS app with SQLite, tray widget, onboarding, and i18n"
git tag desktop-v0.1.0
```
