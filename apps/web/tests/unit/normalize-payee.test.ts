import { describe, expect, it } from 'vitest'
import { normalizePayee } from '@/lib/categorization/normalize-payee'

describe('normalizePayee', () => {
  it('lowercases', () => {
    expect(normalizePayee('AMAZON.FR')).toBe('amazon.fr')
  })
  it('strips ACHAT CB prefix', () => {
    expect(normalizePayee('ACHAT CB CARREFOUR PARIS')).toBe('carrefour paris')
  })
  it('strips trailing 6-digit transaction code', () => {
    expect(normalizePayee('AMAZON 123456')).toBe('amazon')
  })
  it('strips PAIEMENT CARTE prefix', () => {
    expect(normalizePayee('PAIEMENT CARTE NETFLIX')).toBe('netflix')
  })
  it('collapses whitespace', () => {
    expect(normalizePayee('  CAFE   DU  COIN  ')).toBe('cafe du coin')
  })
  it('handles empty string', () => {
    expect(normalizePayee('')).toBe('')
  })
  it('handles whitespace-only', () => {
    expect(normalizePayee('   ')).toBe('')
  })
})
