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
  parseActifsSheet,
  parseSuiviSoldeSheet,
  parseTransactionsSheet,
  type ParsedAccount,
  type ParsedTransaction,
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

async function upsertAccounts(
  parsed: ReadonlyArray<ParsedAccount>,
  usedAccountNames: ReadonlyArray<string>,
): Promise<Map<string, string>> {
  // Collect all account names that either exist in ACTIFS or appear in transactions.
  const allNames = new Set<string>()
  for (const a of parsed) {
    allNames.add(a.name)
  }
  for (const n of usedAccountNames) {
    allNames.add(n)
  }

  // Fetch existing accounts by name
  const existing = await db.select().from(accountsTable)
  const byName = new Map<string, string>()
  for (const row of existing) {
    byName.set(row.name.toLowerCase(), row.id)
  }

  const parsedByLowerName = new Map<string, ParsedAccount>()
  for (const a of parsed) {
    parsedByLowerName.set(a.name.toLowerCase(), a)
  }

  for (const name of allNames) {
    const key = name.toLowerCase()
    if (byName.has(key)) {
      continue
    }
    const parsedAccount = parsedByLowerName.get(key)
    const kind = parsedAccount?.kind ?? 'other'
    const initial = parsedAccount?.initialBalance ?? 0

    const [row] = await db
      .insert(accountsTable)
      .values({
        name,
        kind,
        currentBalance: initial.toFixed(2),
        syncProvider: 'legacy',
      })
      .returning({ id: accountsTable.id })

    if (row) {
      byName.set(key, row.id)
    }
  }

  return byName
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
    // Strip any leading emoji+whitespace from the stored name for loose matching
    const nameKey = c.name.toLowerCase().trim()
    const fullKey = `${groupName}:${nameKey}`.toLowerCase()
    map.set(fullKey, c.id)
    map.set(nameKey, c.id)
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
  const nameKey = name.toLowerCase().trim()
  if (group) {
    const full = `${group.toLowerCase()}:${nameKey}`
    const hit = map.get(full)
    if (hit) {
      return hit
    }
  }
  return map.get(nameKey) ?? null
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
    const accountId = accountByName.get(t.accountName.toLowerCase())
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
    existing.map((r) => (r.date instanceof Date ? r.date.toISOString().slice(0, 10) : String(r.date))),
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

async function recomputeBalances(accountByName: Map<string, string>): Promise<void> {
  for (const accountId of accountByName.values()) {
    const rows = await db
      .select({ amount: transactionsTable.amount })
      .from(transactionsTable)
      .where(
        and(eq(transactionsTable.accountId, accountId), isNull(transactionsTable.deletedAt)),
      )
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
  const accountByName = await upsertAccounts(parsedAccounts, usedAccountNames)
  process.stdout.write(`Accounts upserted: ${accountByName.size}\n`)

  const categoryLookup = await buildCategoryLookup()
  process.stdout.write(`Category lookup entries: ${categoryLookup.size}\n`)

  const txnResult = await importTransactions(parsedTransactions, accountByName, categoryLookup)
  process.stdout.write(
    `Transactions: ${txnResult.inserted} inserted, ${txnResult.skipped} skipped\n`,
  )

  const snapResult = await importSnapshots(parsedSnapshots)
  process.stdout.write(
    `Snapshots: ${snapResult.inserted} inserted, ${snapResult.skipped} skipped\n`,
  )

  process.stdout.write('Recomputing account balances...\n')
  await recomputeBalances(accountByName)
  process.stdout.write('Done.\n')
}

main()
  .then(() => process.exit(0))
  .catch((error: unknown) => {
    const message = error instanceof Error ? error.stack || error.message : String(error)
    process.stderr.write(`Import failed: ${message}\n`)
    process.exit(1)
  })
