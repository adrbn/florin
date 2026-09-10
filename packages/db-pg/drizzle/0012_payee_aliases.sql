ALTER TYPE "public"."category_kind" ADD VALUE IF NOT EXISTS 'adjustment';--> statement-breakpoint
CREATE TABLE IF NOT EXISTS "payee_aliases" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"match_key" text NOT NULL,
	"display_name" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE UNIQUE INDEX IF NOT EXISTS "payee_aliases_match_key_unique" ON "payee_aliases" USING btree ("match_key");