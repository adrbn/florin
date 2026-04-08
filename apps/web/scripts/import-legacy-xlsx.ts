#!/usr/bin/env tsx
/**
 * One-shot importer for the legacy FINANCES.xlsx spreadsheet.
 *
 * Reads the workbook, maps ACTIFS -> accounts, HISTORIQUE TRANSACTIONS ->
 * transactions, and SUIVI SOLDE -> balance_snapshots. Idempotent: re-runs
 * dedupe on (source='legacy_xlsx', legacyId) for transactions and
 * (snapshotDate) for aggregate net worth snapshots (accountId = NULL).
 *
 * Usage (from repo root):
 *   node --env-file=.env --import tsx scripts/import-legacy-xlsx.ts <path.xlsx>
 *
 * The --env-file flag loads DATABASE_URL before the db client is imported
 * (which validates env at module-load time).
 */

import { and, eq, isNull } from 'drizzle-orm'
import * as XLSX from 'xlsx'
import { db } from '../src/db/client'
import {
  accounts as accountsTable,
  balanceSnapshots,
  categories as categoriesTable,
  categoryGroups as categoryGroupsTable,
  transactions as transactionsTable,
} from '../src/db/schema'
import { normalizePayee } from '../src/lib/categorization/normalize-payee'
import {
  type ParsedAccount,
  type ParsedTransaction,
  parseActifsSheet,
  parseSuiviSoldeSheet,
  parseTransactionsSheet,
} from '../src/lib/legacy/parse-xlsx'

const SHEET_HISTORIQUE = 'HISTORIQUE TRANSACTIONS'
const SHEET_SUIVI_SOLDE = 'SUIVI SOLDE'
const SHEET_ACTIFS = 'ACTIFS'

function readSheetRows(workbook: XLSX.WorkBook, name: string): unknown[][] {
  const sheet = workbook.Sheets[name]
  if (!sheet) {
    throw new Error(`Missing sheet: ${name}`)
  }
  return XLSX.utils.sheet_to_json<unknown[]>(sheet, {
    header: 1,
    defval: null,
    raw: true,
  })
}

/**
 * Normalize an account name for matching across the ACTIFS and HISTORIQUE
 * sheets. The legacy spreadsheet has casing and accent inconsistencies between
 * the two sheets — e.g. "Cash" vs "CASH", "Livret A" vs "LIVRET A", and
 * "Prêt étudiant" vs "PRET ETUD". We strip diacritics, lowercase, and collapse
 * whitespace so all variants collide on the same key.
 */
function normalizeAccountKey(name: string): string {
  return name
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .trim()
}

/**
 * Map a few hand-curated aliases that don't survive diacritic-stripping alone
 * (different spellings, abbreviations). Keys and values are pre-normalized.
 */
const ACCOUNT_ALIASES: Readonly<Record<string, string>> = {
  'pret etudiant': 'pret etud',
  'pret etud.': 'pret etud',
  'pret etud': 'pret etud',
}

function resolveAccountKey(name: string): string {
  const base = normalizeAccountKey(name)
  return ACCOUNT_ALIASES[base] ?? base
}

interface UpsertResult {
  byName: Map<string, string>
  authoritativeIds: Set<string>
}

async function upsertAccounts(
  parsed: ReadonlyArray<ParsedAccount>,
  usedAccountNames: ReadonlyArray<string>,
): Promise<UpsertResult> {
  // ACTIFS sheet defines the user's "real" accounts and their authoritative
  // current balances. Anything appearing only in HISTORIQUE column 0 is treated
  // as a historical / secondary bucket — we still create it so the legacy
  // transactions remain queryable, but we mark it excluded from net worth so
  // it doesn't double-count or pollute the headline number.
  const parsedByKey = new Map<string, ParsedAccount>()
  for (const a of parsed) {
    parsedByKey.set(resolveAccountKey(a.name), a)
  }

  const existing = await db.select().from(accountsTable)
  const byName = new Map<string, string>()
  const kindById = new Map<string, string>()
  const includedById = new Map<string, boolean>()
  for (const row of existing) {
    byName.set(resolveAccountKey(row.name), row.id)
    kindById.set(row.id, row.kind)
    includedById.set(row.id, row.isIncludedInNetWorth)
  }

  // 1. Upsert ACTIFS-defined accounts first. These get their authoritative
  //    balance, kind, and is_included_in_net_worth=true from ACTIFS.
  for (const account of parsed) {
    const key = resolveAccountKey(account.name)
    const existingId = byName.get(key)
    if (existingId) {
      await db
        .update(accountsTable)
        .set({
          kind: account.kind,
          currentBalance: account.initialBalance.toFixed(2),
          isIncludedInNetWorth: true,
          updatedAt: new Date(),
        })
        .where(eq(accountsTable.id, existingId))
      continue
    }
    const [row] = await db
      .insert(accountsTable)
      .values({
        name: account.name,
        kind: account.kind,
        currentBalance: account.initialBalance.toFixed(2),
        syncProvider: 'legacy',
        isIncludedInNetWorth: true,
      })
      .returning({ id: accountsTable.id })
    if (row) {
      byName.set(key, row.id)
    }
  }

  // 2. For account names that appear only in transactions, create a
  //    secondary bucket excluded from net worth.
  for (const rawName of usedAccountNames) {
    const key = resolveAccountKey(rawName)
    if (parsedByKey.has(key)) {
      continue // covered by ACTIFS step above
    }
    if (byName.has(key)) {
      continue
    }
    const [row] = await db
      .insert(accountsTable)
      .values({
        name: rawName,
        kind: 'other',
        currentBalance: '0.00',
        syncProvider: 'legacy',
        isIncludedInNetWorth: false,
      })
      .returning({ id: accountsTable.id })
    if (row) {
      byName.set(key, row.id)
    }
  }

  const authoritativeIds = new Set<string>()
  for (const account of parsed) {
    const id = byName.get(resolveAccountKey(account.name))
    if (id) {
      authoritativeIds.add(id)
    }
  }

  return { byName, authoritativeIds }
}

/**
 * Build a lookup keyed by a normalized form of the category name. The legacy
 * XLSX stores categories like "🛒 Food / Courses" while the seeded catalog
 * stores them as "Food / Courses" — we strip leading emoji + whitespace and
 * lowercase on both sides so they collide on the same key.
 */
function normalizeCategoryKey(name: string): string {
  // Drop any leading run of non-letter, non-digit characters (emoji, spaces, punctuation)
  // then lowercase. \p{L}/\p{N} are Unicode letter/number categories.
  return name
    .replace(/^[^\p{L}\p{N}]+/u, '')
    .toLowerCase()
    .trim()
}

async function buildCategoryLookup(): Promise<Map<string, string>> {
  const groups = await db.select().from(categoryGroupsTable)
  const cats = await db.select().from(categoriesTable)
  const groupById = new Map<string, string>()
  for (const g of groups) {
    groupById.set(g.id, g.name)
  }

  const map = new Map<string, string>()
  for (const c of cats) {
    const groupName = groupById.get(c.groupId) ?? ''
    const nameKey = normalizeCategoryKey(c.name)
    if (!nameKey) {
      continue
    }
    const fullKey = `${normalizeCategoryKey(groupName)}:${nameKey}`
    map.set(fullKey, c.id)
    // Don't overwrite a more specific (group:name) match with a bare-name fallback.
    if (!map.has(nameKey)) {
      map.set(nameKey, c.id)
    }
  }
  return map
}

function lookupCategory(
  map: Map<string, string>,
  group: string | null,
  name: string | null,
): string | null {
  if (!name) {
    return null
  }
  const nameKey = normalizeCategoryKey(name)
  if (!nameKey) {
    return null
  }
  if (group) {
    const full = `${normalizeCategoryKey(group)}:${nameKey}`
    const hit = map.get(full)
    if (hit) {
      return hit
    }
  }
  return map.get(nameKey) ?? null
}

/**
 * Re-categorize legacy rows whose categoryId is NULL but whose XLSX category
 * column does match a known category. Lets us repair earlier imports that ran
 * before the category-key normalization fix without re-running the whole
 * import (which would skip the rows by legacyId anyway).
 */
async function backfillCategories(
  txns: ReadonlyArray<ParsedTransaction>,
  categoryLookup: Map<string, string>,
): Promise<number> {
  // Index parsed rows by legacyId for fast lookup
  const byLegacyId = new Map<string, ParsedTransaction>()
  for (const t of txns) {
    if (t.legacyId) {
      byLegacyId.set(t.legacyId, t)
    }
  }

  const uncategorized = await db
    .select({
      id: transactionsTable.id,
      legacyId: transactionsTable.legacyId,
    })
    .from(transactionsTable)
    .where(
      and(
        eq(transactionsTable.source, 'legacy_xlsx'),
        isNull(transactionsTable.categoryId),
        isNull(transactionsTable.deletedAt),
      ),
    )

  let updated = 0
  for (const row of uncategorized) {
    if (!row.legacyId) {
      continue
    }
    const parsed = byLegacyId.get(row.legacyId)
    if (!parsed) {
      continue
    }
    const categoryId = lookupCategory(categoryLookup, parsed.categoryGroup, parsed.categoryName)
    if (!categoryId) {
      continue
    }
    await db
      .update(transactionsTable)
      .set({ categoryId, updatedAt: new Date() })
      .where(eq(transactionsTable.id, row.id))
    updated++
  }
  return updated
}

async function importTransactions(
  txns: ReadonlyArray<ParsedTransaction>,
  accountByName: Map<string, string>,
  categoryLookup: Map<string, string>,
): Promise<{ inserted: number; skipped: number }> {
  // Find existing legacy ids to skip
  const existing = await db
    .select({ legacyId: transactionsTable.legacyId })
    .from(transactionsTable)
    .where(eq(transactionsTable.source, 'legacy_xlsx'))
  const existingLegacyIds = new Set<string>(
    existing.map((r) => r.legacyId ?? '').filter((s) => s.length > 0),
  )

  let inserted = 0
  let skipped = 0

  const BATCH = 500
  const batch: Array<typeof transactionsTable.$inferInsert> = []

  const flush = async (): Promise<void> => {
    if (batch.length === 0) {
      return
    }
    await db.insert(transactionsTable).values(batch).onConflictDoNothing()
    inserted += batch.length
    batch.length = 0
  }

  for (const t of txns) {
    if (existingLegacyIds.has(t.legacyId)) {
      skipped++
      continue
    }
    const accountId = accountByName.get(resolveAccountKey(t.accountName))
    if (!accountId) {
      skipped++
      continue
    }
    const categoryId = lookupCategory(categoryLookup, t.categoryGroup, t.categoryName)

    batch.push({
      accountId,
      occurredAt: t.occurredAt,
      amount: t.amount.toFixed(2),
      payee: t.payee,
      normalizedPayee: normalizePayee(t.payee),
      memo: t.memo,
      categoryId,
      source: 'legacy_xlsx',
      legacyId: t.legacyId,
    })

    if (batch.length >= BATCH) {
      await flush()
    }
  }
  await flush()

  return { inserted, skipped }
}

async function importSnapshots(
  rows: ReadonlyArray<{ snapshotDate: Date; balance: number }>,
): Promise<{ inserted: number; skipped: number }> {
  const existing = await db
    .select({ date: balanceSnapshots.snapshotDate })
    .from(balanceSnapshots)
    .where(isNull(balanceSnapshots.accountId))
  const existingDates = new Set<string>(
    existing.map((r) =>
      r.date instanceof Date ? r.date.toISOString().slice(0, 10) : String(r.date),
    ),
  )

  let inserted = 0
  let skipped = 0
  const batch: Array<typeof balanceSnapshots.$inferInsert> = []
  for (const r of rows) {
    const key = r.snapshotDate.toISOString().slice(0, 10)
    if (existingDates.has(key)) {
      skipped++
      continue
    }
    batch.push({
      snapshotDate: r.snapshotDate,
      balance: r.balance.toFixed(2),
      accountId: null,
    })
    existingDates.add(key)
  }
  if (batch.length > 0) {
    await db.insert(balanceSnapshots).values(batch).onConflictDoNothing()
    inserted = batch.length
  }
  return { inserted, skipped }
}

/**
 * Recompute current_balance from transactions for SECONDARY accounts only.
 *
 * For accounts defined in ACTIFS we trust SOLDE_ACTIF as the authoritative
 * current balance — the legacy HISTORIQUE TRANSACTIONS sheet doesn't include
 * account-opening rows for every account, so summing transactions for, say,
 * LIVRET A produces a nonsense negative number.
 *
 * For auto-created secondary accounts (Caution Rome, PayPal 4x, …) summing
 * transactions is the best estimate we have, and they're excluded from net
 * worth anyway, so the value is informational only.
 */
async function recomputeSecondaryBalances(
  byName: Map<string, string>,
  authoritativeIds: ReadonlySet<string>,
): Promise<void> {
  for (const accountId of byName.values()) {
    if (authoritativeIds.has(accountId)) {
      continue
    }
    const rows = await db
      .select({ amount: transactionsTable.amount })
      .from(transactionsTable)
      .where(and(eq(transactionsTable.accountId, accountId), isNull(transactionsTable.deletedAt)))
    let sum = 0
    for (const r of rows) {
      sum += Number(r.amount)
    }
    await db
      .update(accountsTable)
      .set({ currentBalance: sum.toFixed(2), updatedAt: new Date() })
      .where(eq(accountsTable.id, accountId))
  }
}

async function main(): Promise<void> {
  const path = process.argv[2]
  if (!path) {
    process.stderr.write('Usage: tsx scripts/import-legacy-xlsx.ts <file.xlsx>\n')
    process.exit(1)
  }

  process.stdout.write(`Reading ${path}...\n`)
  const workbook = XLSX.readFile(path)

  const actifsRows = readSheetRows(workbook, SHEET_ACTIFS)
  const histRows = readSheetRows(workbook, SHEET_HISTORIQUE)
  const suiviRows = readSheetRows(workbook, SHEET_SUIVI_SOLDE)

  const parsedAccounts = parseActifsSheet(actifsRows)
  const parsedTransactions = parseTransactionsSheet(histRows)
  const parsedSnapshots = parseSuiviSoldeSheet(suiviRows)

  process.stdout.write(
    `Parsed: ${parsedAccounts.length} accounts, ${parsedTransactions.length} transactions, ${parsedSnapshots.length} snapshots\n`,
  )

  const usedAccountNames = Array.from(new Set(parsedTransactions.map((t) => t.accountName)))
  const { byName: accountByName, authoritativeIds } = await upsertAccounts(
    parsedAccounts,
    usedAccountNames,
  )
  process.stdout.write(
    `Accounts upserted: ${accountByName.size} (${authoritativeIds.size} from ACTIFS, ${accountByName.size - authoritativeIds.size} secondary)\n`,
  )

  const categoryLookup = await buildCategoryLookup()
  process.stdout.write(`Category lookup entries: ${categoryLookup.size}\n`)

  const txnResult = await importTransactions(parsedTransactions, accountByName, categoryLookup)
  process.stdout.write(
    `Transactions: ${txnResult.inserted} inserted, ${txnResult.skipped} skipped\n`,
  )

  const recategorized = await backfillCategories(parsedTransactions, categoryLookup)
  process.stdout.write(`Re-categorized previously imported rows: ${recategorized}\n`)

  const snapResult = await importSnapshots(parsedSnapshots)
  process.stdout.write(
    `Snapshots: ${snapResult.inserted} inserted, ${snapResult.skipped} skipped\n`,
  )

  process.stdout.write('Recomputing secondary account balances...\n')
  await recomputeSecondaryBalances(accountByName, authoritativeIds)
  process.stdout.write('Done.\n')
}

main()
  .then(() => process.exit(0))
  .catch((error: unknown) => {
    const message = error instanceof Error ? error.stack || error.message : String(error)
    process.stderr.write(`Import failed: ${message}\n`)
    process.exit(1)
  })
