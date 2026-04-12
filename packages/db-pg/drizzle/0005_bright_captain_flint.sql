ALTER TABLE "accounts" ADD COLUMN "loan_original_principal" numeric(14, 2);--> statement-breakpoint
ALTER TABLE "accounts" ADD COLUMN "loan_interest_rate" numeric(7, 6);--> statement-breakpoint
ALTER TABLE "accounts" ADD COLUMN "loan_start_date" timestamp;--> statement-breakpoint
ALTER TABLE "accounts" ADD COLUMN "loan_term_months" integer;--> statement-breakpoint
ALTER TABLE "accounts" ADD COLUMN "loan_monthly_payment" numeric(14, 2);--> statement-breakpoint
ALTER TABLE "categories" ADD COLUMN "linked_loan_account_id" uuid;--> statement-breakpoint
ALTER TABLE "categories" ADD CONSTRAINT "categories_linked_loan_account_id_accounts_id_fk" FOREIGN KEY ("linked_loan_account_id") REFERENCES "public"."accounts"("id") ON DELETE set null ON UPDATE no action;