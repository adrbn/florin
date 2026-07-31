import { describe, expect, it } from 'vitest'
import {
  createT,
  normalizeLocale,
  SUPPORTED_LOCALES,
  toLocaleTag,
} from '@florin/core/i18n'
// Loaded by relative path: the dictionaries are internal to @florin/core and
// deliberately not part of its public exports map.
import en from '../../../../packages/core/src/i18n/en.json'
import fr from '../../../../packages/core/src/i18n/fr.json'
import nl from '../../../../packages/core/src/i18n/nl.json'

const DICTS: Record<string, Record<string, string>> = { en, fr, nl }

/** `{name}` placeholders a template expects, order-insensitive. */
function placeholders(s: string): string[] {
  return [...s.matchAll(/\{(\w+)\}/g)].map((m) => m[1]!).sort()
}

describe('i18n dictionaries', () => {
  it('ships a dictionary for every advertised locale', () => {
    for (const { code } of SUPPORTED_LOCALES) {
      expect(DICTS[code], `missing dictionary for ${code}`).toBeDefined()
    }
  })

  // English is the source of truth: the UI passes an inline English fallback at
  // every call site, so a key that exists nowhere else still has to exist here.
  it.each(Object.keys(DICTS).filter((c) => c !== 'en'))(
    '%s has exactly the same keys as en',
    (code) => {
      const dict = DICTS[code]!
      const missing = Object.keys(en).filter((k) => !(k in dict))
      const extra = Object.keys(dict).filter((k) => !(k in en))
      expect(missing, `keys missing from ${code}.json`).toEqual([])
      expect(extra, `keys in ${code}.json with no en counterpart`).toEqual([])
    },
  )

  // A dropped or renamed {placeholder} renders literal braces to the user, or
  // silently loses a number — worse than an untranslated string.
  it.each(Object.keys(DICTS).filter((c) => c !== 'en'))(
    '%s preserves every interpolation placeholder',
    (code) => {
      const dict = DICTS[code]!
      const mismatched = Object.entries(en)
        .filter(([k, v]) => k in dict && placeholders(v).join() !== placeholders(dict[k]!).join())
        .map(([k]) => k)
      expect(mismatched).toEqual([])
    },
  )

  it('has no empty translations', () => {
    for (const [code, dict] of Object.entries(DICTS)) {
      const blank = Object.entries(dict)
        .filter(([, v]) => v.trim() === '')
        .map(([k]) => k)
      expect(blank, `blank values in ${code}.json`).toEqual([])
    }
  })
})

describe('normalizeLocale', () => {
  it('maps regional tags and casing onto a supported locale', () => {
    expect(normalizeLocale('nl')).toBe('nl')
    expect(normalizeLocale('nl-NL')).toBe('nl')
    expect(normalizeLocale('NL')).toBe('nl')
    expect(normalizeLocale('fr-FR')).toBe('fr')
    expect(normalizeLocale('en-GB')).toBe('en')
  })

  it('falls back to en for unsupported or missing input', () => {
    expect(normalizeLocale('de-DE')).toBe('en')
    expect(normalizeLocale('')).toBe('en')
    expect(normalizeLocale(null)).toBe('en')
    expect(normalizeLocale(undefined)).toBe('en')
  })
})

describe('toLocaleTag', () => {
  it('returns the BCP-47 tag Intl needs', () => {
    expect(toLocaleTag('nl')).toBe('nl-NL')
    expect(toLocaleTag('fr')).toBe('fr-FR')
    expect(toLocaleTag('en')).toBe('en-US')
    expect(toLocaleTag('de')).toBe('en-US') // unsupported → en
  })

  it('drives locale-aware currency formatting', () => {
    const fmt = (locale: string) =>
      new Intl.NumberFormat(toLocaleTag(locale), { style: 'currency', currency: 'EUR' }).format(1234.5)
    // Dutch groups with '.' and puts the symbol first — must differ from en-US.
    expect(fmt('nl')).not.toBe(fmt('en'))
    expect(fmt('nl')).toContain('1.234')
  })
})

describe('createT', () => {
  it('returns Dutch for nl', () => {
    const t = createT('nl')
    expect(t('nav.dashboard')).toBe('Overzicht')
    expect(t('kpi.netWorth')).toBe('Nettovermogen')
    expect(t('plan.monthMarch')).toBe('maart')
  })

  it('interpolates variables', () => {
    expect(createT('nl')('gettingStarted.subtitle', { done: 2, total: 4 })).toBe('2 van 4 klaar')
    expect(createT('fr')('gettingStarted.subtitle', { done: 2, total: 4 })).toContain('2')
  })

  it('falls back to English before the inline default for an unknown key', () => {
    // Unknown everywhere → inline fallback is used.
    expect(createT('nl')('__does_not_exist__', 'inline default')).toBe('inline default')
  })

  it('serves every locale without throwing', () => {
    for (const { code } of SUPPORTED_LOCALES) {
      const t = createT(code)
      expect(typeof t('nav.dashboard')).toBe('string')
      expect(t('nav.dashboard').length).toBeGreaterThan(0)
    }
  })
})
