CREATE TABLE "bank_sync_account_results" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"run_id" uuid NOT NULL,
	"account_uid" text NOT NULL,
	"account_id" uuid,
	"balance_fetched" boolean DEFAULT false NOT NULL,
	"balance_error" text,
	"details_error" text,
	"tx_fetched" integer DEFAULT 0 NOT NULL,
	"tx_inserted" integer DEFAULT 0 NOT NULL,
	"tx_error" text
);
--> statement-breakpoint
CREATE TABLE "bank_sync_runs" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"connection_id" uuid NOT NULL,
	"trigger" text DEFAULT 'manual' NOT NULL,
	"started_at" timestamp with time zone DEFAULT now() NOT NULL,
	"finished_at" timestamp with time zone,
	"status" text DEFAULT 'running' NOT NULL,
	"accounts_total" integer DEFAULT 0 NOT NULL,
	"accounts_ok" integer DEFAULT 0 NOT NULL,
	"tx_inserted" integer DEFAULT 0 NOT NULL,
	"error_summary" text,
	"duration_ms" integer
);
--> statement-breakpoint
ALTER TABLE "bank_sync_account_results" ADD CONSTRAINT "bank_sync_account_results_run_id_bank_sync_runs_id_fk" FOREIGN KEY ("run_id") REFERENCES "public"."bank_sync_runs"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "bank_sync_account_results" ADD CONSTRAINT "bank_sync_account_results_account_id_accounts_id_fk" FOREIGN KEY ("account_id") REFERENCES "public"."accounts"("id") ON DELETE set null ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "bank_sync_runs" ADD CONSTRAINT "bank_sync_runs_connection_id_bank_connections_id_fk" FOREIGN KEY ("connection_id") REFERENCES "public"."bank_connections"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
CREATE INDEX "bank_sync_account_results_run_idx" ON "bank_sync_account_results" USING btree ("run_id");--> statement-breakpoint
CREATE INDEX "bank_sync_runs_connection_idx" ON "bank_sync_runs" USING btree ("connection_id","started_at");--> statement-breakpoint
CREATE INDEX "bank_sync_runs_started_idx" ON "bank_sync_runs" USING btree ("started_at");