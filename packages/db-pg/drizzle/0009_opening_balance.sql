ALTER TABLE "accounts" ADD COLUMN "opening_balance" numeric(14, 2) DEFAULT '0' NOT NULL;--> statement-breakpoint

-- Backfill: freeze the currently displayed balance by setting the anchor so
-- that `current_balance = opening_balance + SUM(tx)` holds right now. After
-- this migration, every new transaction moves current_balance by exactly its
-- amount through the recompute helper — no more clobbered legacy balances.
-- Bank-synced providers (enable_banking, pytr) keep opening_balance = 0
-- because their current_balance is authoritative from the sync API and
-- recompute is skipped for them.
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
WHERE "sync_provider" NOT IN ('enable_banking', 'pytr');
