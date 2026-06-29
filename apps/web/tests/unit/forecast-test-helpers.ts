import { randomUUID } from 'node:crypto'
import { createSqliteClient, ensureSchema, type SqliteDB } from '@florin/db-sqlite'
// getRawSqlite is not surfaced through the package exports map; import from source.
import { getRawSqlite } from '../../../../packages/db-sqlite/src/client'

export interface ForecastTestContext {
  db: SqliteDB
  raw: ReturnType<typeof getRawSqlite>
}

/**
 * Spin up an in-memory SQLite database using the real production bootstrap
 * (`createSqliteClient(':memory:')` + `ensureSchema`). Unlike the older
 * inline-DDL helper this stays in lock-step with the live schema, so Phase 1
 * columns (`status`, `recurring_rule_id`, `recurrence_key`, `merge_suggested_tx_id`)
 * and the `recurring_rules` table are always present.
 */
export function makeForecastDb(): ForecastTestContext {
  const db = createSqliteClient(':memory:')
  ensureSchema(db)
  const raw = getRawSqlite(db)
  return { db, raw }
}

/** ISO YYYY-MM-DD for a date offset by `days` relative to now (UTC). */
export function isoOffsetDays(days: number): string {
  return new Date(Date.now() + days * 86_400_000).toISOString().slice(0, 10)
}

/** ISO YYYY-MM-DD for today (UTC). */
export function todayIso(): string {
  return new Date().toISOString().slice(0, 10)
}

/** Fixed RFC-4122 v4 UUIDs so mutations that validate via z.uuid() pass. */
export const ID = {
  groupIncome: 'a1111111-1111-4111-8111-111111111101',
  groupExpense: 'a1111111-1111-4111-8111-111111111102',
  catSalary: 'b2222222-2222-4222-8222-222222222201',
  catRent: 'b2222222-2222-4222-8222-222222222202',
  accountChecking: 'c3333333-3333-4333-8333-333333333301',
  accountSavings: 'c3333333-3333-4333-8333-333333333302',
} as const

export interface SeedAccountInput {
  id?: string
  name?: string
  kind?: string
  openingBalance?: number
  currentBalance?: number
  syncProvider?: string
  isIncludedInNetWorth?: boolean
  isArchived?: boolean
}

/** Insert one account; returns its id. */
export function seedAccount(ctx: ForecastTestContext, input: SeedAccountInput = {}): string {
  const id = input.id ?? randomUUID()
  ctx.raw
    .prepare(
      `INSERT INTO accounts
         (id, name, kind, opening_balance, current_balance, sync_provider,
          is_included_in_net_worth, is_archived)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    )
    .run(
      id,
      input.name ?? 'Checking',
      input.kind ?? 'checking',
      input.openingBalance ?? 0,
      input.currentBalance ?? 0,
      input.syncProvider ?? 'manual',
      input.isIncludedInNetWorth === false ? 0 : 1,
      input.isArchived ? 1 : 0,
    )
  return id
}

export interface SeedTxInput {
  id?: string
  accountId: string
  occurredAt: string
  amount: number
  status?: 'cleared' | 'scheduled'
  source?: string
  payee?: string
  categoryId?: string | null
  externalId?: string | null
  transferPairId?: string | null
  rawData?: string | null
  needsReview?: boolean
}

/** Insert one transaction; returns its id. */
export function seedTx(ctx: ForecastTestContext, input: SeedTxInput): string {
  const id = input.id ?? randomUUID()
  ctx.raw
    .prepare(
      `INSERT INTO transactions
         (id, account_id, occurred_at, amount, status, source, payee,
          category_id, external_id, transfer_pair_id, raw_data, needs_review)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    )
    .run(
      id,
      input.accountId,
      input.occurredAt,
      input.amount,
      input.status ?? 'cleared',
      input.source ?? 'manual',
      input.payee ?? '',
      input.categoryId ?? null,
      input.externalId ?? null,
      input.transferPairId ?? null,
      input.rawData ?? null,
      input.needsReview ? 1 : 0,
    )
  return id
}

/** Read an account's current_balance straight from the raw handle. */
export function readBalance(ctx: ForecastTestContext, accountId: string): number {
  const row = ctx.raw
    .prepare('SELECT current_balance AS b FROM accounts WHERE id = ?')
    .get(accountId) as { b: number } | undefined
  return row?.b ?? Number.NaN
}

/** Count non-deleted transactions, optionally filtered by status. */
export function countTx(ctx: ForecastTestContext, status?: 'cleared' | 'scheduled'): number {
  const sql = status
    ? 'SELECT COUNT(*) AS n FROM transactions WHERE deleted_at IS NULL AND status = ?'
    : 'SELECT COUNT(*) AS n FROM transactions WHERE deleted_at IS NULL'
  const row = (status ? ctx.raw.prepare(sql).get(status) : ctx.raw.prepare(sql).get()) as {
    n: number
  }
  return row.n
}
