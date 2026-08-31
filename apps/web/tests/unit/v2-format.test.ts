import { describe, expect, it } from 'vitest'
import {
  cleanPayee,
  dayLabel,
  humanizePayee,
  initials,
  money,
  seriesVar,
  splitAmount,
} from '@florin/core/components/v2/lib/format'

const EUR = { locale: 'fr-FR', currency: 'EUR' }

describe('splitAmount', () => {
  it('separates the integer part from the cents so the hero can demote them', () => {
    const p = splitAmount(128404.17, EUR)
    expect(p.integer).toBe('128 404')
    expect(p.decimal).toBe(',')
    expect(p.fraction).toBe('17')
    expect(p.currency).toBe('€')
    expect(p.currencyFirst).toBe(false)
  })

  it('widens the narrow no-break space so thousands actually read as grouped', () => {
    // Intl fr-FR emits U+202F, which is a hairline gap at 56px.
    expect(splitAmount(18000, EUR).integer).not.toContain(' ')
    expect(splitAmount(18000, EUR).integer).toContain(' ')
  })

  it('uses a real minus sign, not a hyphen', () => {
    expect(splitAmount(-42, EUR).sign).toBe('−')
  })

  it('emits a plus only when asked', () => {
    expect(splitAmount(42, EUR).sign).toBe('')
    expect(splitAmount(42, { ...EUR, signed: true }).sign).toBe('+')
  })

  it('drops the fraction when decimals are off', () => {
    const p = splitAmount(1234.56, { ...EUR, decimals: false })
    expect(p.fraction).toBe('')
    expect(p.integer).toBe('1 235')
  })

  it('marks currency-first locales so the symbol is not demoted with the cents', () => {
    const p = splitAmount(1234.5, { locale: 'en-US', currency: 'USD' })
    expect(p.currencyFirst).toBe(true)
    expect(p.currency).toBe('$')
  })

  it('never renders NaN', () => {
    expect(splitAmount(Number.NaN, EUR).integer).toBe('0')
    expect(money(Number.POSITIVE_INFINITY, EUR)).toContain('0')
  })

  it('rounds to whole cents rather than leaking float noise', () => {
    expect(splitAmount(0.1 + 0.2, EUR).fraction).toBe('30')
  })
})

describe('cleanPayee / humanizePayee', () => {
  it('strips the payment rail prefix', () => {
    expect(cleanPayee('ACHAT CB DECATHLON')).toBe('DECATHLON')
    expect(cleanPayee('PRLV SEPA EDF')).toBe('EDF')
    expect(cleanPayee('CB PAIEMENT CARREFOUR')).toBe('CARREFOUR')
  })

  it('strips the trailing capture date and card number', () => {
    expect(cleanPayee('ACHAT CB SUPERMARCHE 17.08.2026 CARTE 4589')).toBe('SUPERMARCHE')
  })

  it('never returns an empty string', () => {
    expect(cleanPayee('CB')).toBe('CB')
    expect(cleanPayee('   ')).toBe('')
  })

  it('de-shouts token by token, so one lowercase word does not spare the rest', () => {
    // "CARTE" is not leading here, so it survives cleanPayee and just gets
    // cased — the point is that the trailing "Du" no longer spares the rest.
    expect(humanizePayee('REGULARISATION CARTE BANCAIRE Du 18/08')).toBe(
      'Regularisation Carte Bancaire Du 18/08',
    )
  })

  it('keeps acronyms uppercase but cases real words', () => {
    expect(humanizePayee('EDF')).toBe('EDF')
    expect(humanizePayee('SNCF CONNECT')).toBe('SNCF Connect')
    // Vowel-bearing four-letter brands really are written as words.
    expect(humanizePayee('IKEA FRANCE')).toBe('Ikea France')
    expect(humanizePayee('LIDL')).toBe('Lidl')
  })

  it('leaves genuinely mixed-case brands untouched', () => {
    expect(humanizePayee('iTunes')).toBe('iTunes')
    expect(humanizePayee("McDonald's Paris")).toBe("McDonald's Paris")
  })
})

describe('initials', () => {
  it('takes one letter from each of the first two words', () => {
    expect(initials('Crf St Martin')).toBe('CS')
  })

  it('falls back to two letters of a single word', () => {
    expect(initials('Decathlon')).toBe('DE')
  })

  it('degrades to a bullet rather than an empty bubble', () => {
    expect(initials('   ')).toBe('·')
  })
})

describe('seriesVar', () => {
  it('is stable for the same label', () => {
    expect(seriesVar('Carrefour')).toBe(seriesVar('Carrefour'))
  })

  it('stays inside the declared palette', () => {
    for (const label of ['a', 'Courses', 'Loyer', 'Voyages', 'Santé', 'x'.repeat(50)]) {
      expect(seriesVar(label)).toMatch(/^var\(--v2-s[1-8]\)$/)
    }
  })
})

describe('dayLabel', () => {
  const labels = { today: "Aujourd'hui", yesterday: 'Hier' }
  const now = new Date(2026, 7, 23, 15, 0, 0)

  it('names today and yesterday', () => {
    expect(dayLabel(new Date(2026, 7, 23, 2, 0), 'fr-FR', labels, now)).toBe("Aujourd'hui")
    expect(dayLabel(new Date(2026, 7, 22, 23, 59), 'fr-FR', labels, now)).toBe('Hier')
  })

  it('compares calendar days, not elapsed hours', () => {
    // 20 hours earlier but a different date — that is "yesterday", not "today".
    expect(dayLabel(new Date(2026, 7, 22, 19, 0), 'fr-FR', labels, now)).toBe('Hier')
  })

  it('omits the year inside the current one and adds it outside', () => {
    expect(dayLabel(new Date(2026, 2, 4), 'fr-FR', labels, now)).not.toContain('2026')
    expect(dayLabel(new Date(2025, 2, 4), 'fr-FR', labels, now)).toContain('2025')
  })
})
