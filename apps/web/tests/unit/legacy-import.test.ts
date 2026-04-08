import { describe, expect, it } from 'vitest'
import {
  excelSerialToDate,
  mapActifCategoryToKind,
  parseActifsSheet,
  parseSuiviSoldeSheet,
  parseTransactionsSheet,
} from '@/lib/legacy/parse-xlsx'

describe('excelSerialToDate', () => {
  it('converts Excel serial 1 to 1899-12-31', () => {
    const d = excelSerialToDate(1)
    expect(d.toISOString().slice(0, 10)).toBe('1899-12-31')
  })

  it('converts a 2025-era serial to a correct JS date', () => {
    // Excel serial 45717 = 2025-03-01 (validated against XLSX.SSF.parse_date_code)
    const d = excelSerialToDate(45717)
    expect(d.toISOString().slice(0, 10)).toBe('2025-03-01')
  })
})

describe('mapActifCategoryToKind', () => {
  it('maps Liquidités → checking', () => {
    expect(mapActifCategoryToKind('Liquidités')).toBe('checking')
  })

  it('maps Épargne → savings', () => {
    expect(mapActifCategoryToKind('Épargne')).toBe('savings')
  })

  it('maps Dette → loan', () => {
    expect(mapActifCategoryToKind('Dette')).toBe('loan')
  })

  it('falls back to other for unknown categories', () => {
    expect(mapActifCategoryToKind('Random')).toBe('other')
  })
})

describe('parseActifsSheet', () => {
  it('parses account rows and skips the header', () => {
    const rows: ReadonlyArray<ReadonlyArray<unknown>> = [
      ['NOM_ACTIF', 'CATEGORIE', 'SOLDE_ACTIF'],
      ['CCP', 'Liquidités', 980.79],
      ['LIVRET A', 'Épargne', 3000],
      [null, null, null],
    ]
    const accounts = parseActifsSheet(rows)
    expect(accounts).toHaveLength(2)
    expect(accounts[0]).toEqual({ name: 'CCP', kind: 'checking', initialBalance: 980.79 })
    expect(accounts[1]).toEqual({ name: 'LIVRET A', kind: 'savings', initialBalance: 3000 })
  })
})

describe('parseTransactionsSheet', () => {
  it('treats outflow as negative and inflow as positive and skips header/blank rows', () => {
    const rows: ReadonlyArray<ReadonlyArray<unknown>> = [
      [
        'Account',
        'Date',
        'Outflow',
        'Inflow',
        'Payee',
        'Group/Cat',
        'Memo',
        'Group',
        'Category',
        null,
        'Cleared',
      ],
      ['CCP', 45717, 12.5, 0, 'Carrefour', 'Needs: Food', 'lunch', 'Needs', 'Food', null, 'uuid-1'],
      [
        'CCP',
        45718,
        0,
        1500,
        'Salaire',
        'Revenus: Salaires',
        null,
        'Revenus',
        'Salaires',
        null,
        'uuid-2',
      ],
      [null, null, null, null, null, null, null, null, null, null, ''],
    ]
    const txns = parseTransactionsSheet(rows)
    expect(txns).toHaveLength(2)
    expect(txns[0]?.amount).toBe(-12.5)
    expect(txns[0]?.legacyId).toBe('uuid-1')
    expect(txns[0]?.categoryGroup).toBe('Needs')
    expect(txns[0]?.categoryName).toBe('Food')
    expect(txns[1]?.amount).toBe(1500)
  })
})

describe('parseSuiviSoldeSheet', () => {
  it('parses date+balance pairs and skips rows missing either', () => {
    const rows: ReadonlyArray<ReadonlyArray<unknown>> = [
      [null, 'DATE', 'PATRI. BRUT'],
      [null, 45717, 6118],
      [null, 45748, 5538],
      [null, null, null],
      [null, 45839, null],
    ]
    const snaps = parseSuiviSoldeSheet(rows)
    expect(snaps).toHaveLength(2)
    expect(snaps[0]?.balance).toBe(6118)
    expect(snaps[0]?.snapshotDate.toISOString().slice(0, 10)).toBe('2025-03-01')
  })
})
