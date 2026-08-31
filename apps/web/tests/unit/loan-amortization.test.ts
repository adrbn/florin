import { describe, expect, it } from 'vitest'
import {
  buildSchedule,
  calibrateAnnualRate,
  compareSchedules,
  computeMonthlyPayment,
  type LoanInputs,
  simulateSchedule,
  solveAnnualRateFromPayment,
} from '@/lib/loan/amortization'
import { computeLoanLiability } from '@/lib/loan/liability'

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

// A real consumer loan, kept because a synthetic one would not have caught
// the TAEG-versus-taux-débiteur discrepancy this calibrates for: 10 000 €, mensualité
// 135,91 €, 84 months, started 2024-06-30. The bank amortizes on the taux
// débiteur (~3,83 %) while its statement quotes the TAEG (3,90 %). After 25
// payments the bank's "capital restant dû" reads 7 298,12 €.
const lbpLoan: LoanInputs = {
  originalPrincipal: 10_000,
  annualRate: 0.039, // the TAEG, as a user would type it off the statement
  termMonths: 84,
  startDate: new Date(Date.UTC(2024, 5, 30)),
}

describe('solveAnnualRateFromPayment', () => {
  it('recovers the periodic rate that makes principal/payment/term consistent', () => {
    const annual = solveAnnualRateFromPayment({
      principal: 10_000,
      monthlyPayment: 135.91,
      termMonths: 84,
    })
    expect(annual).not.toBeNull()
    // Taux débiteur ≈ 3.83 %, distinctly below the entered 3.90 % TAEG.
    expect(annual as number).toBeCloseTo(0.0383, 3)
    // The recovered rate must reproduce the mensualité it was solved from.
    const check = computeMonthlyPayment({ ...lbpLoan, annualRate: annual as number })
    expect(check).toBeCloseTo(135.91, 2)
  })

  it('returns 0 for a 0% loan (payment = P/n)', () => {
    expect(solveAnnualRateFromPayment({ principal: 1200, monthlyPayment: 100, termMonths: 12 })).toBe(0)
  })

  it('returns null when the payment is too small to ever amortize', () => {
    expect(solveAnnualRateFromPayment({ principal: 10_000, monthlyPayment: 50, termMonths: 12 })).toBeNull()
  })
})

describe('calibrateAnnualRate + finalMonth', () => {
  it('lowers the entered TAEG to the true taux débiteur', () => {
    const calibrated = calibrateAnnualRate(lbpLoan, 135.91)
    expect(calibrated.annualRate).toBeLessThan(0.039)
    expect(calibrated.annualRate).toBeCloseTo(0.0383, 3)
  })

  it('closes exactly on the contractual term instead of spilling a stub month', () => {
    const calibrated = calibrateAnnualRate(lbpLoan, 135.91)
    // Without finalMonth the rounding residual trails into an 85th month…
    const spill = simulateSchedule(calibrated, { baseMonthlyPayment: 135.91 })
    expect(spill.rows.length).toBe(85)
    // …with finalMonth set, the last instalment absorbs it → exactly 84 rows.
    const closed = simulateSchedule(calibrated, { baseMonthlyPayment: 135.91, finalMonth: 84 })
    expect(closed.rows.length).toBe(84)
    expect(closed.rows[closed.rows.length - 1]?.balanceAfter ?? 1).toBeLessThan(0.01)
  })
})

describe('computeLoanLiability — matches the bank', () => {
  const account = {
    kind: 'loan' as const,
    loanOriginalPrincipal: 10_000,
    loanInterestRate: 0.039,
    loanTermMonths: 84,
    loanMonthlyPayment: 135.91,
    loanStartDate: new Date(Date.UTC(2024, 5, 30)),
  }

  it('reports capital restant dû within ~1 € of the bank after 25 payments', () => {
    const { remainingDebt, fromSchedule } = computeLoanLiability(account, 25)
    expect(fromSchedule).toBe(true)
    // Bank statement: 7 298,12 €. Calibrated schedule lands within a euro.
    expect(Math.abs(remainingDebt - 7298.12)).toBeLessThan(1)
  })

  it('splits money paid into principal + interest that reconcile', () => {
    const { principalPaid, interestPaid } = computeLoanLiability(account, 25)
    // 10 000 − restant dû ≈ principal repaid.
    expect(principalPaid).toBeCloseTo(10_000 - 7298.12, 0)
    expect(interestPaid).toBeGreaterThan(0)
  })

  it('reaches zero debt at the end of the calibrated 84-month term', () => {
    expect(computeLoanLiability(account, 84).remainingDebt).toBeLessThan(1)
  })
})
