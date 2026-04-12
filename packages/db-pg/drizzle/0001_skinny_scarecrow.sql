CREATE TABLE "balance_snapshots" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"snapshot_date" timestamp NOT NULL,
	"account_id" uuid,
	"balance" numeric(14, 2) NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "categorization_rules" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"priority" integer DEFAULT 0 NOT NULL,
	"category_id" uuid NOT NULL,
	"match_payee_regex" text,
	"match_min_amount" numeric(14, 2),
	"match_max_amount" numeric(14, 2),
	"match_account_id" uuid,
	"is_active" boolean DEFAULT true NOT NULL,
	"hits_count" integer DEFAULT 0 NOT NULL,
	"last_hit_at" timestamp with time zone,
	"note" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "transactions" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"account_id" uuid NOT NULL,
	"occurred_at" timestamp NOT NULL,
	"recorded_at" timestamp with time zone DEFAULT now() NOT NULL,
	"amount" numeric(14, 2) NOT NULL,
	"currency" text DEFAULT 'EUR' NOT NULL,
	"payee" text DEFAULT '' NOT NULL,
	"normalized_payee" text DEFAULT '' NOT NULL,
	"memo" text,
	"category_id" uuid,
	"source" "transaction_source" NOT NULL,
	"external_id" text,
	"legacy_id" text,
	"is_pending" boolean DEFAULT false NOT NULL,
	"transfer_pair_id" uuid,
	"raw_data" text,
	"deleted_at" timestamp with time zone,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "balance_snapshots" ADD CONSTRAINT "balance_snapshots_account_id_accounts_id_fk" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "categorization_rules" ADD CONSTRAINT "categorization_rules_category_id_categories_id_fk" FOREIGN KEY ("category_id") REFERENCES "public"."categories"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "categorization_rules" ADD CONSTRAINT "categorization_rules_match_account_id_accounts_id_fk" FOREIGN KEY ("match_account_id") REFERENCES "public"."accounts"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "transactions" ADD CONSTRAINT "transactions_account_id_accounts_id_fk" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "transactions" ADD CONSTRAINT "transactions_category_id_categories_id_fk" FOREIGN KEY ("category_id") REFERENCES "public"."categories"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "balance_snapshots_date_account_unique" ON "balance_snapshots" USING btree ("snapshot_date","account_id");--> statement-breakpoint
CREATE INDEX "transactions_account_date_idx" ON "transactions" USING btree ("account_id","occurred_at");--> statement-breakpoint
CREATE INDEX "transactions_category_date_idx" ON "transactions" USING btree ("category_id","occurred_at");--> statement-breakpoint
CREATE UNIQUE INDEX "transactions_source_external_unique" ON "transactions" USING btree ("source","external_id") WHERE "transactions"."external_id" IS NOT NULL;--> statement-breakpoint
CREATE UNIQUE INDEX "transactions_legacy_unique" ON "transactions" USING btree ("legacy_id") WHERE "transactions"."legacy_id" IS NOT NULL;--> statement-breakpoint
CREATE INDEX "transactions_not_deleted_idx" ON "transactions" USING btree ("occurred_at") WHERE "transactions"."deleted_at" IS NULL;