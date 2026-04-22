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
}
