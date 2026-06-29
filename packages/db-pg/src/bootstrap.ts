import { sql } from 'drizzle-orm'
import type { PgDB } from './client'

/**
 * Idempotent runtime schema patches for Postgres.
 *
 * The web app runs `drizzle-kit migrate` out-of-band, but relying on that for
 * every hotfix means a user who forgets `make migrate` after a deploy ends up
 * on a broken build. For small additive changes (new nullable columns, new
 * defaults) we can safely re-run ADD COLUMN IF NOT EXISTS on every startup,
 * backfill the new column once, and not worry about it.
 *
 * This is NOT a replacement for real migrations — anything that needs a
 * structural change (renames, drops, FK changes) still has to go through
 * drizzle-kit. Use this only for "add an anchor column and backfill" style
 * patches.
 */
export async function ensurePgRuntimePatches(db: PgDB): Promise<void> {
  // opening_balance anchor (see packages/db-pg/src/actions/helpers.ts).
  // If the column is brand new, we freeze the currently displayed balance by
  // computing the opening value that makes `opening + SUM(tx) = current_balance`
  // hold right now. Bank-synced providers keep openingBalance = 0 since their
  // currentBalance is authoritative from the sync API.
  await db.execute(
    sql`ALTER TABLE "accounts" ADD COLUMN IF NOT EXISTS "opening_balance" numeric(14, 2) NOT NULL DEFAULT '0'`,
  )
  await db.execute(sql`
    UPDATE "accounts"
    SET "opening_balance" = "current_balance"::numeric - COALESCE(
      (
        SELECT SUM(amount)::numeric
        FROM "transactions"
        WHERE "transactions"."account_id" = "accounts"."id"
          AND "transactions"."deleted_at" IS NULL
      ),
      0
    )
    WHERE "sync_provider" NOT IN ('enable_banking', 'pytr')
      AND "opening_balance" = 0
      AND "current_balance" <> 0
  `)

  // Phase 1 — forecast & reconciliation. recurring_rules is created first (it
  // is the FK target of transactions.recurring_rule_id), then the new
  // transactions columns + partial indexes. All idempotent; existing rows
  // default to status='cleared' so balances are unchanged at deploy time.
  await db.execute(sql`
    CREATE TABLE IF NOT EXISTS "recurring_rules" (
      "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
      "name" text NOT NULL,
      "kind" text DEFAULT 'transfer' NOT NULL,
      "account_id" uuid NOT NULL REFERENCES "accounts"("id") ON DELETE CASCADE,
      "to_account_id" uuid REFERENCES "accounts"("id") ON DELETE CASCADE,
      "amount" numeric(14, 2) NOT NULL,
      "payee" text DEFAULT '' NOT NULL,
      "category_id" uuid REFERENCES "categories"("id") ON DELETE SET NULL,
      "currency" text DEFAULT 'EUR' NOT NULL,
      "memo" text,
      "frequency" text DEFAULT 'monthly' NOT NULL,
      "interval" integer DEFAULT 1 NOT NULL,
      "day_of_month" integer DEFAULT 1 NOT NULL,
      "start_date" timestamp NOT NULL,
      "end_date" timestamp,
      "is_active" boolean DEFAULT true NOT NULL,
      "last_materialized_date" timestamp,
      "created_at" timestamp with time zone DEFAULT now() NOT NULL,
      "updated_at" timestamp with time zone DEFAULT now() NOT NULL
    )
  `)
  await db.execute(
    sql`CREATE INDEX IF NOT EXISTS "recurring_rules_active_idx" ON "recurring_rules" ("is_active")`,
  )
  await db.execute(
    sql`CREATE INDEX IF NOT EXISTS "recurring_rules_account_idx" ON "recurring_rules" ("account_id")`,
  )

  await db.execute(
    sql`ALTER TABLE "transactions" ADD COLUMN IF NOT EXISTS "status" text DEFAULT 'cleared' NOT NULL`,
  )
  await db.execute(
    sql`ALTER TABLE "transactions" ADD COLUMN IF NOT EXISTS "recurring_rule_id" uuid REFERENCES "recurring_rules"("id") ON DELETE SET NULL`,
  )
  await db.execute(
    sql`ALTER TABLE "transactions" ADD COLUMN IF NOT EXISTS "recurrence_key" text`,
  )
  await db.execute(
    sql`ALTER TABLE "transactions" ADD COLUMN IF NOT EXISTS "merge_suggested_tx_id" uuid`,
  )
  await db.execute(
    sql`CREATE INDEX IF NOT EXISTS "transactions_status_idx" ON "transactions" ("status","occurred_at") WHERE "deleted_at" IS NULL`,
  )
  await db.execute(
    sql`CREATE INDEX IF NOT EXISTS "transactions_recurring_rule_idx" ON "transactions" ("recurring_rule_id") WHERE "recurring_rule_id" IS NOT NULL`,
  )
  await db.execute(
    sql`CREATE UNIQUE INDEX IF NOT EXISTS "transactions_recurrence_key_unique" ON "transactions" ("recurrence_key","account_id") WHERE "recurrence_key" IS NOT NULL`,
  )
}
