import { describe, expect, it } from 'vitest'
import { parseAmountSearch } from '@florin/core/lib/transactions'

describe('parseAmountSearch', () => {
  it('parses a dot decimal to its absolute value', () => {
    expect(parseAmountSearch('22.99')).toBe(22.99)
  })
  it('parses a comma decimal (fr-FR)', () => {
    expect(parseAmountSearch('22,99')).toBe(22.99)
  })
  it('is sign-agnostic — a negative query returns the magnitude', () => {
    expect(parseAmountSearch('-22.99')).toBe(22.99)
  })
  it('parses a plain integer', () => {
    expect(parseAmountSearch('100')).toBe(100)
  })
  it('strips a currency symbol and grouping spaces', () => {
    expect(parseAmountSearch('1 000,50 €')).toBe(1000.5)
  })
  it('rounds to cents', () => {
    expect(parseAmountSearch('22.999')).toBe(23)
  })
  it('returns null for non-numeric text (no amount match for "netflix")', () => {
    expect(parseAmountSearch('netflix')).toBeNull()
  })
  it('returns null for alphanumeric queries', () => {
    expect(parseAmountSearch('22abc')).toBeNull()
  })
  it('returns null for an empty / partial query', () => {
    expect(parseAmountSearch('')).toBeNull()
    expect(parseAmountSearch('-')).toBeNull()
    expect(parseAmountSearch('.')).toBeNull()
  })
})
