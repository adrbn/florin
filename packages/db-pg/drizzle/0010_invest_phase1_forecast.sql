CREATE TABLE "recurring_rules" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"name" text NOT NULL,
	"kind" text DEFAULT 'transfer' NOT NULL,
	"account_id" uuid NOT NULL,
	"to_account_id" uuid,
	"amount" numeric(14, 2) NOT NULL,
	"payee" text DEFAULT '' NOT NULL,
	"category_id" uuid,
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
);
--> statement-breakpoint
ALTER TABLE "transactions" ADD COLUMN "status" text DEFAULT 'cleared' NOT NULL;--> statement-breakpoint
ALTER TABLE "transactions" ADD COLUMN "recurring_rule_id" uuid;--> statement-breakpoint
ALTER TABLE "transactions" ADD COLUMN "recurrence_key" text;--> statement-breakpoint
ALTER TABLE "transactions" ADD COLUMN "merge_suggested_tx_id" uuid;--> statement-breakpoint
ALTER TABLE "recurring_rules" ADD CONSTRAINT "recurring_rules_account_id_accounts_id_fk" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "recurring_rules" ADD CONSTRAINT "recurring_rules_to_account_id_accounts_id_fk" FOREIGN KEY ("to_account_id") REFERENCES "public"."accounts"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "recurring_rules" ADD CONSTRAINT "recurring_rules_category_id_categories_id_fk" FOREIGN KEY ("category_id") REFERENCES "public"."categories"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "recurring_rules_active_idx" ON "recurring_rules" USING btree ("is_active");--> statement-breakpoint
CREATE INDEX "recurring_rules_account_idx" ON "recurring_rules" USING btree ("account_id");--> statement-breakpoint
ALTER TABLE "transactions" ADD CONSTRAINT "transactions_recurring_rule_id_recurring_rules_id_fk" FOREIGN KEY ("recurring_rule_id") REFERENCES "public"."recurring_rules"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "transactions_status_idx" ON "transactions" USING btree ("status","occurred_at") WHERE "transactions"."deleted_at" IS NULL;--> statement-breakpoint
CREATE INDEX "transactions_recurring_rule_idx" ON "transactions" USING btree ("recurring_rule_id") WHERE "transactions"."recurring_rule_id" IS NOT NULL;--> statement-breakpoint
CREATE UNIQUE INDEX "transactions_recurrence_key_unique" ON "transactions" USING btree ("recurrence_key","account_id") WHERE "transactions"."recurrence_key" IS NOT NULL;