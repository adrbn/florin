import { describe, expect, it } from 'vitest'
import { cleanDisplayName } from '@florin/core/lib/categorization'

describe('cleanDisplayName', () => {
  it("strips the 'de' preposition, refs and trailing path from the reported PayPal string", () => {
    const raw =
      'de paypal europe s.a, l. et cie s.c.a, ref : 1041355744819, 1041355744819/paypal mensuel'
    expect(cleanDisplayName(raw)).toBe('Paypal Europe S.A')
  })
  it('title-cases an all-lowercase name', () => {
    expect(cleanDisplayName('amazon prime mensuel')).toBe('Amazon Prime Mensuel')
  })
  it('title-cases an ALL CAPS name', () => {
    expect(cleanDisplayName('ORANGE SA')).toBe('Orange SA')
  })
  it('trusts an already mixed-case name', () => {
    expect(cleanDisplayName('PayPal Europe')).toBe('PayPal Europe')
  })
  it('strips a leading banking prefix', () => {
    expect(cleanDisplayName('PRLV SPOTIFY')).toBe('Spotify')
  })
  it("drops a French elision prefix (d')", () => {
    expect(cleanDisplayName("d'orange sa")).toBe('Orange SA')
  })
  it('returns empty string for empty / null input', () => {
    expect(cleanDisplayName('')).toBe('')
    expect(cleanDisplayName(null)).toBe('')
    expect(cleanDisplayName(undefined)).toBe('')
  })
  it('uppercases dotted acronyms', () => {
    expect(cleanDisplayName('paypal europe s.c.a')).toBe('Paypal Europe S.C.A')
  })
})
