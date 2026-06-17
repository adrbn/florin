import { describe, expect, it } from 'vitest'
import { parseDecimalInput } from '@florin/core/lib/format'

describe('parseDecimalInput', () => {
  it('parses a plain integer string', () => {
    expect(parseDecimalInput('350000')).toBe(350000)
  })
  it('parses a dot decimal', () => {
    expect(parseDecimalInput('3.5')).toBe(3.5)
  })
  it('parses a comma decimal (fr-FR keyboards)', () => {
    expect(parseDecimalInput('22,99')).toBe(22.99)
  })
  it('parses negative values', () => {
    expect(parseDecimalInput('-12.34')).toBe(-12.34)
  })
  it('returns the fallback for an empty string (the zero-on-clear fix)', () => {
    expect(parseDecimalInput('', 0)).toBe(0)
    expect(parseDecimalInput('', 1)).toBe(1)
  })
  it('returns the fallback for transient typing states', () => {
    expect(parseDecimalInput('-')).toBe(0)
    expect(parseDecimalInput('.')).toBe(0)
    expect(parseDecimalInput('-.')).toBe(0)
  })
  it('returns the fallback for non-numeric garbage', () => {
    expect(parseDecimalInput('abc', 0)).toBe(0)
  })
  it('ignores surrounding and inner whitespace', () => {
    expect(parseDecimalInput('  1 000  ')).toBe(1000)
  })
})
