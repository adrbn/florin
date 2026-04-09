import { describe, expect, it } from 'vitest'
import {
  buildSchedule,
  compareSchedules,
  computeMonthlyPayment,
  type LoanInputs,
  simulateSchedule,
} from '@/lib/loan/amortization'

// 100k€ borrowed at 3.5% over 20 years (240 mo) — canonical amortization
// example for sanity-checking the math against any public loan calculator.
const sampleLoan: LoanInputs = {
  originalPrincipal: 100_000,
  annualRate: 0.035,
  termMonths: 240,
  startDate: new Date(Date.UTC(2026, 0, 1)),
}

describe('computeMonthlyPayment', () => {
  it('matches the closed-form P·r·(1+r)^n / ((1+r)^n - 1) value', () => {
    // Expected from any loan calculator: ~579.96€
    const m = computeMonthlyPayment(sampleLoan)
    expect(m).toBeCloseTo(579.96, 1)
  })

  it('handles 0% rate as a flat P/n split', () => {
    expect(computeMonthlyPayment({ ...sampleLoan, annualRate: 0 })).toBeCloseTo(416.67, 1)
  })
})

describe('buildSchedule', () => {
  it('produces exactly termMonths rows and lands on a zero balance', () => {
    const { rows, summary } = buildSchedule(sampleLoan)
    expect(rows.length).toBeLessThanOrEqual(240)
    expect(rows.length).toBeGreaterThanOrEqual(239)
    // Rounding slop can eat the last row — ensure the tail balance is near-zero.
    expect(rows[rows.length - 1]?.balanceAfter ?? 0).toBeLessThan(1)
    // Total paid ≈ mensualité * months, within a few euros of rounding slack.
    const expectedTotal = summary.monthlyPayment * summary.months
    expect(Math.abs(summary.totalPaid - expectedTotal)).toBeLessThan(5)
  })

  it('breaks down the first row into interest + principal correctly', () => {
    const { rows } = buildSchedule(sampleLoan)
    const first = rows[0]
    expect(first).toBeTruthy()
    if (!first) return
    // Month-1 interest = 100000 * 0.035/12 ≈ 291.67
    expect(first.interest).toBeCloseTo(291.67, 1)
    expect(first.payment).toBeCloseTo(579.96, 1)
    expect(first.principal + first.interest).toBeCloseTo(first.payment, 1)
  })
})

describe('simulateSchedule with extra payments', () => {
  it('shortens the schedule when a lump sum is applied early', () => {
    const base = buildSchedule(sampleLoan)
    const simulated = simulateSchedule(sampleLoan, {
      baseMonthlyPayment: base.summary.monthlyPayment,
      lumpSumAmount: 20_000,
      lumpSumMonth: 12,
    })
    const cmp = compareSchedules(base, simulated)
    expect(cmp.monthsSaved).toBeGreaterThan(40)
    expect(cmp.interestSaved).toBeGreaterThan(10_000)
    expect(simulated.rows[simulated.rows.length - 1]?.balanceAfter ?? 0).toBeLessThan(1)
  })

  it('is a no-op when extra payments are zero', () => {
    const base = buildSchedule(sampleLoan)
    const simulated = simulateSchedule(sampleLoan, {
      baseMonthlyPayment: base.summary.monthlyPayment,
      extraPayments: {},
    })
    expect(simulated.summary.months).toBe(base.summary.months)
    expect(simulated.summary.totalInterest).toBeCloseTo(base.summary.totalInterest, 0)
  })
})
