import { describe, expect, it } from 'vitest'
import { projectGoal } from '@florin/core/lib/goal'

describe('projectGoal', () => {
  it('reaches a target with positive contribution + return', () => {
    // Frozen "now" so the reach date is deterministic.
    const now = new Date('2026-01-15T00:00:00Z')
    const p = projectGoal(
      {
        currentValue: 20_000,
        monthlyContribution: 500,
        annualReturnPct: 7,
        target: 100_000,
      },
      now,
    )

    // The target is reachable within the 100-year horizon.
    expect(p.monthsToReach).not.toBeNull()
    expect(Number.isFinite(p.monthsToReach as number)).toBe(true)
    expect((p.monthsToReach as number) > 0).toBe(true)

    // contributed + marketGrowth ≈ target (the split spans the whole goal).
    expect(p.contributed + p.marketGrowth).toBeCloseTo(p.target, 6)

    // contributed = currentValue + monthlyContribution * monthsToReach.
    expect(p.contributed).toBeCloseTo(
      20_000 + 500 * (p.monthsToReach as number),
      6,
    )
    expect(p.marketGrowth).toBeGreaterThanOrEqual(0)

    // reachDateIso is a YYYY-MM-DD string in the future.
    expect(p.reachDateIso).toMatch(/^\d{4}-\d{2}-\d{2}$/)
    expect(new Date(`${p.reachDateIso}T00:00:00Z`).getTime()).toBeGreaterThan(now.getTime())
  })

  it('returns monthsToReach = 0 when currentValue ≥ target', () => {
    const now = new Date('2026-01-15T00:00:00Z')
    const p = projectGoal(
      {
        currentValue: 120_000,
        monthlyContribution: 500,
        annualReturnPct: 7,
        target: 100_000,
      },
      now,
    )
    expect(p.monthsToReach).toBe(0)
    // Reach date is "now" (month offset 0) and contributed equals currentValue.
    expect(p.reachDateIso).toBe('2026-01-15')
    expect(p.contributed).toBe(120_000)
  })

  it('returns null monthsToReach when contribution = 0 AND return = 0 AND currentValue < target', () => {
    const p = projectGoal({
      currentValue: 50_000,
      monthlyContribution: 0,
      annualReturnPct: 0,
      target: 100_000,
    })
    expect(p.monthsToReach).toBeNull()
    expect(p.reachDateIso).toBeNull()
    expect(p.contributed).toBe(0)
    expect(p.marketGrowth).toBe(0)
  })
})
