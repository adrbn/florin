import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'
import { createV2T } from '@florin/core/components/v2/i18n'

/**
 * The v2 surface ships its own dictionary rather than adding to the 910-key
 * app one. It needs the same guarantees: every locale carries every key, every
 * key carries the same placeholders, and counted strings read correctly at 1.
 */

const dir = '../../../../packages/core/src/components/v2/i18n'
const load = (locale: string): Record<string, string> =>
  JSON.parse(
    readFileSync(fileURLToPath(new URL(`${dir}/${locale}.json`, import.meta.url)), 'utf8'),
  ) as Record<string, string>

const fr = load('fr')
const en = load('en')
const nl = load('nl')

const placeholders = (s: string): string[] => (s.match(/\{(\w+)\}/g) ?? []).sort()

describe('v2 dictionary parity', () => {
  it('ships a non-trivial dictionary', () => {
    expect(Object.keys(fr).length).toBeGreaterThan(200)
  })

  for (const [name, dict] of [
    ['en', en],
    ['nl', nl],
  ] as const) {
    it(`${name} covers every fr key`, () => {
      expect(Object.keys(fr).filter((k) => !(k in dict))).toEqual([])
    })

    it(`${name} adds no key fr does not have`, () => {
      expect(Object.keys(dict).filter((k) => !(k in fr))).toEqual([])
    })

    it(`${name} uses the same placeholders as fr`, () => {
      const mismatched = Object.keys(fr).filter(
        (k) => placeholders(fr[k]!).join() !== placeholders(dict[k]!).join(),
      )
      expect(mismatched).toEqual([])
    })
  }

  it('never leaves a translation empty', () => {
    for (const [name, dict] of [
      ['fr', fr],
      ['en', en],
      ['nl', nl],
    ] as const) {
      const blank = Object.entries(dict)
        .filter(([, v]) => v.trim() === '')
        .map(([k]) => `${name}:${k}`)
      expect(blank).toEqual([])
    }
  })

  it('pairs every _one variant with a base key', () => {
    const orphans = Object.keys(fr)
      .filter((k) => k.endsWith('_one'))
      .filter((k) => !(k.replace(/_one$/, '') in fr))
    expect(orphans).toEqual([])
  })
})

describe('createV2T', () => {
  it('resolves a v2 key in the requested locale', () => {
    expect(createV2T('fr')('v2.nav.overview')).toBe('Aperçu')
    expect(createV2T('nl')('v2.nav.overview')).toBe('Overzicht')
  })

  it('falls through to the base app dictionary for non-v2 keys', () => {
    // 'nav.dashboard' lives in the shared dictionary, not the v2 one.
    expect(createV2T('fr')('nav.dashboard', 'Dashboard')).not.toBe('nav.dashboard')
  })

  it('still honours an inline fallback for a key nobody defines', () => {
    expect(createV2T('fr')('v2.nope.nothing', 'Fallback')).toBe('Fallback')
  })

  it('interpolates named placeholders', () => {
    expect(createV2T('fr')('v2.overview.daysLeft', { count: 8 })).toContain('8')
  })

  it('picks the singular form at count 1', () => {
    const t = createV2T('fr')
    expect(t('v2.activity.count', { count: 1 })).toBe('1 opération')
    expect(t('v2.activity.count', { count: 12 })).toBe('12 opérations')
  })

  it('follows the locale plural rules rather than a hardcoded n===1', () => {
    // French treats 0 as the "one" category; English does not.
    expect(createV2T('fr')('v2.activity.count', { count: 0 })).toBe('0 opération')
    expect(createV2T('en')('v2.activity.count', { count: 0 })).toBe('0 transactions')
  })
})
