import { describe, expect, it } from 'vitest'
import { isNewer, parseVersion } from '@florin/core/lib/version'

describe('parseVersion', () => {
  it('parses bare, v-prefixed, and Florin-v tag forms', () => {
    expect(parseVersion('1.2.3')).toEqual([1, 2, 3])
    expect(parseVersion('v1.2.3')).toEqual([1, 2, 3])
    expect(parseVersion('Florin-v1.2.24')).toEqual([1, 2, 24])
    expect(parseVersion('  florin-v0.10.0  ')).toEqual([0, 10, 0])
  })

  it('ignores pre-release / build suffixes', () => {
    expect(parseVersion('1.2.3-beta.1')).toEqual([1, 2, 3])
    expect(parseVersion('Florin-v1.2.3+build.5')).toEqual([1, 2, 3])
  })

  it('returns null for malformed input', () => {
    expect(parseVersion('')).toBeNull()
    expect(parseVersion('latest')).toBeNull()
    expect(parseVersion('1.2')).toBeNull()
    expect(parseVersion('vX.Y.Z')).toBeNull()
  })
})

describe('isNewer', () => {
  it('detects a newer version across each component', () => {
    expect(isNewer('1.2.25', '1.2.24')).toBe(true)
    expect(isNewer('1.3.0', '1.2.99')).toBe(true)
    expect(isNewer('2.0.0', '1.9.9')).toBe(true)
    expect(isNewer('Florin-v1.2.25', '1.2.24')).toBe(true)
  })

  it('is false for equal or older versions', () => {
    expect(isNewer('1.2.24', '1.2.24')).toBe(false)
    expect(isNewer('1.2.23', '1.2.24')).toBe(false)
    expect(isNewer('1.0.0', '1.2.24')).toBe(false)
  })

  it('is false when either side is unparseable (never nag blindly)', () => {
    expect(isNewer('garbage', '1.2.24')).toBe(false)
    expect(isNewer('1.2.25', 'garbage')).toBe(false)
  })
})
