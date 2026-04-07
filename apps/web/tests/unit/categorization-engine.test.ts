import { describe, expect, it } from 'vitest'
import { type CandidateTxn, matchRule, type Rule } from '@/lib/categorization/engine'

const baseRule: Rule = {
  id: 'r1',
  priority: 0,
  categoryId: 'cat-default',
  isActive: true,
  matchPayeeRegex: null,
  matchMinAmount: null,
  matchMaxAmount: null,
  matchAccountId: null,
}

const baseTxn: CandidateTxn = {
  payee: 'amazon',
  amount: -42,
  accountId: 'acc-1',
}

describe('matchRule', () => {
  it('returns null when no rules match', () => {
    const rules: Rule[] = [
      { ...baseRule, id: 'r1', matchPayeeRegex: 'netflix', categoryId: 'cat-streaming' },
    ]
    expect(matchRule(baseTxn, rules)).toBeNull()
  })

  it('matches a payee regex case-insensitively', () => {
    const rules: Rule[] = [
      { ...baseRule, id: 'r1', matchPayeeRegex: 'AMAZON', categoryId: 'cat-shopping' },
    ]
    expect(matchRule(baseTxn, rules)).toBe('cat-shopping')
  })

  it('respects priority order (higher priority wins)', () => {
    const rules: Rule[] = [
      {
        ...baseRule,
        id: 'r1',
        priority: 1,
        matchPayeeRegex: 'amazon',
        categoryId: 'cat-low',
      },
      {
        ...baseRule,
        id: 'r2',
        priority: 10,
        matchPayeeRegex: 'amazon',
        categoryId: 'cat-high',
      },
    ]
    expect(matchRule(baseTxn, rules)).toBe('cat-high')
  })

  it('skips inactive rules', () => {
    const rules: Rule[] = [
      {
        ...baseRule,
        id: 'r1',
        matchPayeeRegex: 'amazon',
        categoryId: 'cat-shopping',
        isActive: false,
      },
    ]
    expect(matchRule(baseTxn, rules)).toBeNull()
  })

  it('AND semantics across payee + amount range', () => {
    const rules: Rule[] = [
      {
        ...baseRule,
        id: 'r1',
        matchPayeeRegex: 'amazon',
        matchMinAmount: -100,
        matchMaxAmount: -10,
        categoryId: 'cat-shopping',
      },
    ]
    expect(matchRule({ ...baseTxn, amount: -42 }, rules)).toBe('cat-shopping')
    expect(matchRule({ ...baseTxn, amount: -5 }, rules)).toBeNull()
  })

  it('AND semantics across accountId', () => {
    const rules: Rule[] = [
      {
        ...baseRule,
        id: 'r1',
        matchPayeeRegex: 'amazon',
        matchAccountId: 'acc-other',
        categoryId: 'cat-shopping',
      },
    ]
    expect(matchRule(baseTxn, rules)).toBeNull()
    expect(matchRule({ ...baseTxn, accountId: 'acc-other' }, rules)).toBe('cat-shopping')
  })

  it('skips rules with malformed regex', () => {
    const rules: Rule[] = [
      { ...baseRule, id: 'r1', matchPayeeRegex: '[invalid', categoryId: 'cat-bad' },
      {
        ...baseRule,
        id: 'r2',
        priority: 0,
        matchPayeeRegex: 'amazon',
        categoryId: 'cat-good',
      },
    ]
    expect(matchRule(baseTxn, rules)).toBe('cat-good')
  })

  it('returns the first matching rule when multiple share priority', () => {
    const rules: Rule[] = [
      { ...baseRule, id: 'r1', priority: 5, matchPayeeRegex: 'amazon', categoryId: 'cat-a' },
      { ...baseRule, id: 'r2', priority: 5, matchPayeeRegex: 'amazon', categoryId: 'cat-b' },
    ]
    expect(matchRule(baseTxn, rules)).toBe('cat-a')
  })
})
