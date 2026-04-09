#!/usr/bin/env tsx
/**
 * One-shot backfill for the student loan (`Prêt étudiant`) monthly payments
 * that were missing from FINANCES.xlsx.
 *
 * Background: the legacy spreadsheet only contained the 2026-01 and 2026-03
 * debits for the loan — everything from June 2024 through December 2025 was
 * tracked in YNAB but never exported. This script inserts one -135.91 EUR
 * CCP → Prêt étudiant payment per missing month, matching the structure of
 * rows the app already creates via the loan-mirror mechanism (shared
 * `transferPairId`, mirror on the loan account, category = "Student loans").
 *
 * Idempotent: a month is skipped when CCP already has a row categorized as
 * Student loans in that calendar month. Re-running the script after a real
 * bank debit lands for e.g. April 2026 will just leave the new data alone.
 *
 * Usage (from repo root, inside the LXC or with DATABASE_URL set):
 *   node --env-file=.env --import tsx \
 *     apps/web/scripts/backfill-student-loan-payments.ts
 *
 * Or inside the docker-compose container where DATABASE_URL is already set:
 *   docker compose exec web node --import tsx scripts/backfill-student-loan-payments.ts
 */

import { randomUUID } from 'node:crypto'
import { and, eq, gte, isNull, lt, sql } from 'drizzle-orm'
import { db } from '../src/db/client'
import { accounts, categories, transactions } from '../src/db/schema'
import { normalizePayee } from '../src/lib/categorization/normalize-payee'

const CCP_NAME = 'CCP'
const LOAN_NAME = 'Prêt étudiant'
const CATEGORY_NAME = 'Student loans'
const MONTHLY_AMOUNT = 135.91
// The real Banque Postale debit lands on the 29th of each month. We reuse
// the same date so the backfilled rows look like the real ones from the
// bank, just earlier.
const DAY_OF_MONTH = 29
// Inclusive start: June 2024.
const START_YEAR = 2024
const START_MONTH = 6 // June
// Inclusive end: March 2026 — the month of the most recent confirmed
// payment in the user's YNAB screenshot. April 2026 hasn't been paid yet.
const END_YEAR = 2026
const END_MONTH = 3 // March
// Payee string matches the real Banque Postale libellé so the normalized
// payee collides with the two enable_banking rows already in the DB — this
// is useful later when the categorization engine auto-matches new debits.
const PAYEE =
  'PRELEVEMENT DE LA BANQUE POSTALE, NSUMER FI, MENSUALITE PRET ETUDIANT/APPRENT'
const MEMO = 'backfill: YNAB historical payment'

interface TargetMonth {
  year: number
  month: number // 1-12
  occurredAt: Date
}

function buildTargetMonths(): TargetMonth[] {
  const out: TargetMonth[] = []
  let y = START_YEAR
  let m = START_MONTH
  while (y < END_YEAR || (y === END_YEAR && m <= END_MONTH)) {
    // Clamp to the last day of the month in case DAY_OF_MONTH doesn't exist.
    const daysInMonth = new Date(y, m, 0).getDate()
    const day = Math.min(DAY_OF_MONTH, daysInMonth)
    out.push({
      year: y,
      month: m,
      // Local midnight so the occurred_at timestamp lines up with the same
      // date users see in the UI regardless of their timezone.
      occurredAt: new Date(y, m - 1, day),
    })
    m++
    if (m > 12) {
      m = 1
      y++
    }
  }
  return out
}

async function main(): Promise<void> {
  const ccpAccount = await db.query.accounts.findFirst({
    where: eq(accounts.name, CCP_NAME),
  })
  if (!ccpAccount) throw new Error(`Account not found: ${CCP_NAME}`)

  const loanAccount = await db.query.accounts.findFirst({
    where: eq(accounts.name, LOAN_NAME),
  })
  if (!loanAccount) throw new Error(`Account not found: ${LOAN_NAME}`)
  if (loanAccount.kind !== 'loan') {
    throw new Error(`Account ${LOAN_NAME} is not kind=loan`)
  }

  const loanCategory = await db.query.categories.findFirst({
    where: eq(categories.name, CATEGORY_NAME),
  })
  if (!loanCategory) throw new Error(`Category not found: ${CATEGORY_NAME}`)
  if (loanCategory.linkedLoanAccountId !== loanAccount.id) {
    throw new Error(
      `Category ${CATEGORY_NAME} is not linked to ${LOAN_NAME} (linked=${loanCategory.linkedLoanAccountId ?? 'null'})`,
    )
  }

  const months = buildTargetMonths()
  process.stdout.write(
    `Planning ${months.length} monthly payments (${START_YEAR}-${String(START_MONTH).padStart(2, '0')} → ${END_YEAR}-${String(END_MONTH).padStart(2, '0')})\n`,
  )

  let inserted = 0
  let skipped = 0

  for (const t of months) {
    const monthStart = new Date(t.year, t.month - 1, 1)
    const nextMonthStart = new Date(t.year, t.month, 1)

    // Dedup: if CCP already has ANY row in this calendar month categorized as
    // Student loans, assume it's the real payment and skip the backfill.
    const existing = await db
      .select({ id: transactions.id })
      .from(transactions)
      .where(
        and(
          eq(transactions.accountId, ccpAccount.id),
          eq(transactions.categoryId, loanCategory.id),
          gte(transactions.occurredAt, monthStart),
          lt(transactions.occurredAt, nextMonthStart),
          isNull(transactions.deletedAt),
        ),
      )
      .limit(1)

    if (existing.length > 0) {
      process.stdout.write(
        `  skip ${t.year}-${String(t.month).padStart(2, '0')} (already has a Student loans row)\n`,
      )
      skipped++
      continue
    }

    const pairId = randomUUID()
    const mirrorPayee = `↳ ${PAYEE}`

    // Insert the CCP (origin) row + the Prêt étudiant mirror in a single
    // batch so we never leave a half-pair on failure.
    await db.insert(transactions).values([
      {
        accountId: ccpAccount.id,
        occurredAt: t.occurredAt,
        amount: (-MONTHLY_AMOUNT).toFixed(2),
        currency: 'EUR',
        payee: PAYEE,
        normalizedPayee: normalizePayee(PAYEE),
        memo: MEMO,
        categoryId: loanCategory.id,
        source: 'manual',
        transferPairId: pairId,
        needsReview: false,
      },
      {
        accountId: loanAccount.id,
        occurredAt: t.occurredAt,
        amount: MONTHLY_AMOUNT.toFixed(2),
        currency: 'EUR',
        payee: mirrorPayee,
        normalizedPayee: normalizePayee(mirrorPayee),
        memo: 'auto: loan payment mirror',
        categoryId: null,
        source: 'manual',
        transferPairId: pairId,
        needsReview: false,
      },
    ])
    process.stdout.write(
      `  insert ${t.occurredAt.toISOString().slice(0, 10)} -${MONTHLY_AMOUNT.toFixed(2)} EUR\n`,
    )
    inserted++
  }

  // Recompute both account balances from the transaction history. CCP +
  // loan both just got new rows, so both need a pass. We do it in SQL to
  // mirror recomputeAccountBalance() in server/actions/transactions.ts
  // without needing to import from a 'use server' module.
  for (const accountId of [ccpAccount.id, loanAccount.id]) {
    const result = await db
      .select({
        total: sql<string>`COALESCE(SUM(${transactions.amount}), 0)::text`,
      })
      .from(transactions)
      .where(and(eq(transactions.accountId, accountId), isNull(transactions.deletedAt)))
    const total = result[0]?.total ?? '0'
    await db
      .update(accounts)
      .set({ currentBalance: total, updatedAt: new Date() })
      .where(eq(accounts.id, accountId))
  }

  process.stdout.write(
    `\nDone: ${inserted} inserted, ${skipped} skipped (already present).\n`,
  )
}

main()
  .then(() => process.exit(0))
  .catch((error: unknown) => {
    const message = error instanceof Error ? error.stack || error.message : String(error)
    process.stderr.write(`Backfill failed: ${message}\n`)
    process.exit(1)
  })
