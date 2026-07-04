import { describe, expect, it } from 'vitest'
import { monthlyNetWorthTrend } from '@florin/core/lib/trend'
import type { PatrimonyPoint } from '@florin/core/types'

const DAYS_PER_MONTH = 30.4368

describe('monthlyNetWorthTrend', () => {
  it('returns 0 for fewer than two points', () => {
    expect(monthlyNetWorthTrend([])).toBe(0)
    expect(monthlyNetWorthTrend([{ date: '2026-01-01', balance: 100 }])).toBe(0)
  })

  it('recovers a constant daily slope as a per-month figure', () => {
    // +10 €/day over 30 contiguous daily points → 10 × 30.4368 €/month.
    const points: PatrimonyPoint[] = Array.from({ length: 30 }, (_, i) => ({
      date: `2026-01-${String(i + 1).padStart(2, '0')}`,
      balance: 1000 + i * 10,
    }))
    expect(monthlyNetWorthTrend(points)).toBeCloseTo(10 * DAYS_PER_MONTH, 6)
  })

  it('is negative when net worth declines', () => {
    const points: PatrimonyPoint[] = Array.from({ length: 10 }, (_, i) => ({
      date: `2026-02-${String(i + 1).padStart(2, '0')}`,
      balance: 5000 - i * 25,
    }))
    expect(monthlyNetWorthTrend(points)).toBeCloseTo(-25 * DAYS_PER_MONTH, 6)
  })

  it('ignores projected (forecast) points', () => {
    const points: PatrimonyPoint[] = [
      { date: '2026-03-01', balance: 1000 },
      { date: '2026-03-02', balance: 1010 },
      { date: '2026-03-03', balance: 1020 },
      // A wild forecast point must not bend the realized trend.
      { date: '2026-03-04', balance: 99999, projected: true },
    ]
    expect(monthlyNetWorthTrend(points)).toBeCloseTo(10 * DAYS_PER_MONTH, 6)
  })
})
