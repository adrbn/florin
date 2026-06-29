import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'

// en.json / fr.json are flat objects keyed by dot-notation strings.
const enPath = fileURLToPath(new URL('../../../../packages/core/src/i18n/en.json', import.meta.url))
const frPath = fileURLToPath(new URL('../../../../packages/core/src/i18n/fr.json', import.meta.url))

function loadKeys(path: string): string[] {
  const json = JSON.parse(readFileSync(path, 'utf8')) as Record<string, unknown>
  return Object.keys(json).sort()
}

describe('i18n key parity (en.json ↔ fr.json)', () => {
  const enKeys = loadKeys(enPath)
  const frKeys = loadKeys(frPath)

  it('both files parse and are non-empty', () => {
    expect(enKeys.length).toBeGreaterThan(0)
    expect(frKeys.length).toBeGreaterThan(0)
  })

  it('en has no keys missing from fr', () => {
    const missingInFr = enKeys.filter((k) => !frKeys.includes(k))
    expect(missingInFr).toEqual([])
  })

  it('fr has no keys missing from en', () => {
    const missingInEn = frKeys.filter((k) => !enKeys.includes(k))
    expect(missingInEn).toEqual([])
  })

  it('key sets are exactly identical', () => {
    expect(enKeys).toEqual(frKeys)
  })
})
