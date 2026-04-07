/**
 * Parse the legacy FINANCES.xlsx workbook into normalized rows.
 *
 * Sheets consumed:
 *   - HISTORIQUE TRANSACTIONS: one row per transaction (Account, Date, Outflow, Inflow, Payee, ...)
 *   - SUIVI SOLDE: per-date gross net worth snapshot (DATE, PATRI. BRUT)
 *   - ACTIFS: account definitions with initial balance (NOM_ACTIF, CATEGORIE, SOLDE_ACTIF)
 *
 * Excel stores dates as serial numbers. We convert them to JS Dates using the
 * 1900 date system (Excel's default). Time-of-day component is discarded for
 * transactions; we keep the date only.
 */

export interface ParsedAccount {
  name: string
  kind: LegacyAccountKind
  initialBalance: number
}

export type LegacyAccountKind =
  | 'checking'
  | 'savings'
  | 'cash'
  | 'loan'
  | 'broker_cash'
  | 'broker_portfolio'
  | 'other'

export interface ParsedTransaction {
  accountName: string
  occurredAt: Date
  amount: number // signed: positive = inflow, negative = outflow
  payee: string
  memo: string | null
  categoryGroup: string | null
  categoryName: string | null
  legacyId: string
}

export interface ParsedNetWorthSnapshot {
  snapshotDate: Date
  balance: number
}

export interface ParsedWorkbook {
  accounts: ParsedAccount[]
  transactions: ParsedTransaction[]
  snapshots: ParsedNetWorthSnapshot[]
}

const EXCEL_EPOCH_UTC_MS = Date.UTC(1899, 11, 30) // Excel serial 0 = 1899-12-30
const MS_PER_DAY = 86_400_000

export function excelSerialToDate(serial: number): Date {
  // Strip time component for day-level precision
  const whole = Math.floor(serial)
  return new Date(EXCEL_EPOCH_UTC_MS + whole * MS_PER_DAY)
}

export function mapActifCategoryToKind(category: string): LegacyAccountKind {
  const lower = category.toLowerCase()
  if (lower.includes('liquid')) {
    return 'checking'
  }
  if (lower.includes('épargne') || lower.includes('epargne') || lower.includes('savings')) {
    return 'savings'
  }
  if (lower.includes('dette') || lower.includes('loan')) {
    return 'loan'
  }
  if (lower.includes('broker') || lower.includes('bourse') || lower.includes('titre')) {
    return 'broker_portfolio'
  }
  return 'other'
}

type CellRow = ReadonlyArray<unknown>

function cellToString(cell: unknown): string {
  if (cell === null || cell === undefined) {
    return ''
  }
  return String(cell).trim()
}

function cellToNumber(cell: unknown): number {
  if (cell === null || cell === undefined || cell === '') {
    return 0
  }
  if (typeof cell === 'number') {
    return cell
  }
  const parsed = Number(cell)
  return Number.isFinite(parsed) ? parsed : 0
}

function cellIsEmpty(cell: unknown): boolean {
  return cell === null || cell === undefined || cell === ''
}

/**
 * Parse the ACTIFS sheet (account definitions).
 *
 * Expected header row (row index 5):
 *   NOM_ACTIF | CATEGORIE | SOLDE_ACTIF
 */
export function parseActifsSheet(rows: ReadonlyArray<CellRow>): ParsedAccount[] {
  const accounts: ParsedAccount[] = []
  for (const row of rows) {
    if (!row || row.length < 3) {
      continue
    }
    const name = cellToString(row[0])
    const category = cellToString(row[1])
    if (!name || !category || name === 'NOM_ACTIF') {
      continue
    }
    const initialBalance = cellToNumber(row[2])
    accounts.push({
      name,
      kind: mapActifCategoryToKind(category),
      initialBalance,
    })
  }
  return accounts
}

/**
 * Parse the HISTORIQUE TRANSACTIONS sheet.
 *
 * Expected columns (0-based):
 *   0: Account       1: Date           2: Outflow       3: Inflow
 *   4: Payee         5: Group/Category 6: Memo          7: Category Group
 *   8: Category      9: —              10: Cleared (uuid)  11: Date réelle
 */
export function parseTransactionsSheet(rows: ReadonlyArray<CellRow>): ParsedTransaction[] {
  const txns: ParsedTransaction[] = []
  for (const row of rows) {
    if (!row || row.length < 9) {
      continue
    }
    const accountName = cellToString(row[0])
    const dateCell = row[1]
    if (!accountName || cellIsEmpty(dateCell)) {
      continue
    }
    if (accountName === 'Account') {
      // header
      continue
    }
    const outflow = cellToNumber(row[2])
    const inflow = cellToNumber(row[3])
    const amount = inflow - outflow
    const payee = cellToString(row[4])
    const memo = cellToString(row[6]) || null
    const group = cellToString(row[7]) || null
    const category = cellToString(row[8]) || null
    const legacyId = cellToString(row[10]) || `row-${txns.length}`

    txns.push({
      accountName,
      occurredAt: excelSerialToDate(cellToNumber(dateCell)),
      amount,
      payee,
      memo,
      categoryGroup: group,
      categoryName: category,
      legacyId,
    })
  }
  return txns
}

/**
 * Parse the SUIVI SOLDE sheet (net worth snapshots).
 *
 * Expected columns (0-based):
 *   1: DATE (excel serial)    2: PATRI. BRUT (number)
 */
export function parseSuiviSoldeSheet(rows: ReadonlyArray<CellRow>): ParsedNetWorthSnapshot[] {
  const snapshots: ParsedNetWorthSnapshot[] = []
  for (const row of rows) {
    if (!row) {
      continue
    }
    const dateCell = row[1]
    const balanceCell = row[2]
    if (cellIsEmpty(dateCell) || cellIsEmpty(balanceCell)) {
      continue
    }
    if (typeof dateCell !== 'number' || typeof balanceCell !== 'number') {
      continue
    }
    snapshots.push({
      snapshotDate: excelSerialToDate(dateCell),
      balance: balanceCell,
    })
  }
  return snapshots
}
