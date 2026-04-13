import { NextResponse } from 'next/server'
import { sql } from 'drizzle-orm'
import { db } from '@/db/client'
import {
  accounts,
  bankConnections,
  categories,
  categorizationRules,
  categoryGroups,
  transactions,
} from '@/db/schema'

export const dynamic = 'force-dynamic'

/**
 * Import a Florin JSON export into the local SQLite database.
 * Clears existing data first, then inserts the imported rows.
 * Handles both camelCase (JS) and snake_case (PG) field names.
 */
export async function POST(request: Request) {
  try {
    const payload = await request.json()

    if (!payload || !payload.schemaVersion) {
      return NextResponse.json({ error: 'Invalid export file' }, { status: 400 })
    }

    // Delete existing data in dependency order
    db.run(sql`DELETE FROM transactions`)
    db.run(sql`DELETE FROM categorization_rules`)
    db.run(sql`DELETE FROM categories`)
    db.run(sql`DELETE FROM category_groups`)
    db.run(sql`DELETE FROM bank_connections`)
    db.run(sql`DELETE FROM accounts`)
    db.run(sql`DELETE FROM balance_snapshots`)
    // Don't clear settings — keep PIN, locale, currency prefs

    const imported = {
      accounts: 0,
      categoryGroups: 0,
      categories: 0,
      rules: 0,
      transactions: 0,
      bankConnections: 0,
    }

    // Insert category groups first (categories depend on them)
    if (payload.categoryGroups?.length) {
      for (const row of payload.categoryGroups) {
        await db
          .insert(categoryGroups)
          .values({
            id: row.id,
            name: row.name,
            kind: row.kind ?? 'expense',
            displayOrder: row.displayOrder ?? row.display_order ?? 0,
            color: row.color ?? null,
            createdAt: row.createdAt ?? row.created_at ?? new Date().toISOString(),
          })
          .onConflictDoNothing()
      }
      imported.categoryGroups = payload.categoryGroups.length
    }

    // Insert bank connections
    if (payload.bankConnections?.length) {
      for (const row of payload.bankConnections) {
        await db
          .insert(bankConnections)
          .values({
            id: row.id,
            provider: row.provider ?? 'enable_banking',
            sessionId: row.sessionId ?? row.session_id ?? `imported-${row.id}`,
            aspspName: row.aspspName ?? row.aspsp_name ?? '',
            aspspCountry: row.aspspCountry ?? row.aspsp_country ?? '',
            status: row.status ?? 'active',
            validUntil: row.validUntil ?? row.valid_until ?? '',
            syncStartDate: row.syncStartDate ?? row.sync_start_date ?? new Date().toISOString(),
            lastSyncedAt: row.lastSyncedAt ?? row.last_synced_at ?? null,
            lastSyncError: row.lastSyncError ?? row.last_sync_error ?? null,
            createdAt: row.createdAt ?? row.created_at ?? new Date().toISOString(),
            updatedAt: row.updatedAt ?? row.updated_at ?? new Date().toISOString(),
          })
          .onConflictDoNothing()
      }
      imported.bankConnections = payload.bankConnections.length
    }

    // Insert accounts
    if (payload.accounts?.length) {
      for (const row of payload.accounts) {
        await db
          .insert(accounts)
          .values({
            id: row.id,
            name: row.name,
            kind: row.kind ?? 'checking',
            institution: row.institution ?? null,
            currency: row.currency ?? 'EUR',
            iban: row.iban ?? null,
            isActive: row.isActive ?? row.is_active ?? true,
            isArchived: row.isArchived ?? row.is_archived ?? false,
            isIncludedInNetWorth:
              row.isIncludedInNetWorth ?? row.is_included_in_net_worth ?? true,
            currentBalance: row.currentBalance ?? row.current_balance ?? 0,
            lastSyncedAt: row.lastSyncedAt ?? row.last_synced_at ?? null,
            syncProvider: row.syncProvider ?? row.sync_provider ?? 'manual',
            syncExternalId: row.syncExternalId ?? row.sync_external_id ?? null,
            bankConnectionId: row.bankConnectionId ?? row.bank_connection_id ?? null,
            displayColor: row.displayColor ?? row.display_color ?? null,
            displayIcon: row.displayIcon ?? row.display_icon ?? null,
            displayOrder: row.displayOrder ?? row.display_order ?? 0,
            loanOriginalPrincipal:
              row.loanOriginalPrincipal ?? row.loan_original_principal ?? null,
            loanInterestRate: row.loanInterestRate ?? row.loan_interest_rate ?? null,
            loanStartDate: row.loanStartDate ?? row.loan_start_date ?? null,
            loanTermMonths: row.loanTermMonths ?? row.loan_term_months ?? null,
            loanMonthlyPayment: row.loanMonthlyPayment ?? row.loan_monthly_payment ?? null,
            createdAt: row.createdAt ?? row.created_at ?? new Date().toISOString(),
            updatedAt: row.updatedAt ?? row.updated_at ?? new Date().toISOString(),
          })
          .onConflictDoNothing()
      }
      imported.accounts = payload.accounts.length
    }

    // Insert categories (depend on category_groups)
    if (payload.categories?.length) {
      for (const row of payload.categories) {
        await db
          .insert(categories)
          .values({
            id: row.id,
            groupId: row.groupId ?? row.group_id,
            name: row.name,
            emoji: row.emoji ?? null,
            displayOrder: row.displayOrder ?? row.display_order ?? 0,
            isFixed: row.isFixed ?? row.is_fixed ?? false,
            isArchived: row.isArchived ?? row.is_archived ?? false,
            linkedLoanAccountId:
              row.linkedLoanAccountId ?? row.linked_loan_account_id ?? null,
            createdAt: row.createdAt ?? row.created_at ?? new Date().toISOString(),
          })
          .onConflictDoNothing()
      }
      imported.categories = payload.categories.length
    }

    // Insert categorization rules
    if (payload.categorizationRules?.length) {
      for (const row of payload.categorizationRules) {
        await db
          .insert(categorizationRules)
          .values({
            id: row.id,
            priority: row.priority ?? 0,
            categoryId: row.categoryId ?? row.category_id,
            matchPayeeRegex: row.matchPayeeRegex ?? row.match_payee_regex ?? row.pattern ?? null,
            matchMinAmount: row.matchMinAmount ?? row.match_min_amount ?? null,
            matchMaxAmount: row.matchMaxAmount ?? row.match_max_amount ?? null,
            matchAccountId: row.matchAccountId ?? row.match_account_id ?? null,
            isActive: row.isActive ?? row.is_active ?? true,
            hitsCount: row.hitsCount ?? row.hits_count ?? 0,
            lastHitAt: row.lastHitAt ?? row.last_hit_at ?? null,
            note: row.note ?? null,
            createdAt: row.createdAt ?? row.created_at ?? new Date().toISOString(),
            updatedAt: row.updatedAt ?? row.updated_at ?? new Date().toISOString(),
          })
          .onConflictDoNothing()
      }
      imported.rules = payload.categorizationRules.length
    }

    // Insert transactions (depend on accounts and categories)
    if (payload.transactions?.length) {
      const txs = payload.transactions
      for (let i = 0; i < txs.length; i += 100) {
        const chunk = txs.slice(i, i + 100)
        for (const row of chunk) {
          await db
            .insert(transactions)
            .values({
              id: row.id,
              accountId: row.accountId ?? row.account_id,
              occurredAt: row.occurredAt ?? row.occurred_at ?? row.date ?? '',
              recordedAt:
                row.recordedAt ?? row.recorded_at ?? row.occurredAt ?? row.occurred_at ?? '',
              amount: row.amount,
              currency: row.currency ?? 'EUR',
              payee: row.payee ?? '',
              normalizedPayee: row.normalizedPayee ?? row.normalized_payee ?? '',
              memo: row.memo ?? null,
              categoryId: row.categoryId ?? row.category_id ?? null,
              source: row.source ?? 'manual',
              externalId: row.externalId ?? row.external_id ?? null,
              legacyId: row.legacyId ?? row.legacy_id ?? null,
              isPending: row.isPending ?? row.is_pending ?? false,
              needsReview: row.needsReview ?? row.needs_review ?? false,
              transferPairId: row.transferPairId ?? row.transfer_pair_id ?? null,
              rawData: row.rawData ?? row.raw_data ?? null,
              deletedAt: row.deletedAt ?? row.deleted_at ?? null,
              createdAt: row.createdAt ?? row.created_at ?? new Date().toISOString(),
              updatedAt: row.updatedAt ?? row.updated_at ?? new Date().toISOString(),
            })
            .onConflictDoNothing()
        }
      }
      imported.transactions = payload.transactions.length
    }

    return NextResponse.json({ success: true, imported })
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Import failed'
    return NextResponse.json({ error: message }, { status: 500 })
  }
}
