/**
 * Loan amortization helpers — pure functions, no I/O.
 *
 * The standard fixed-rate amortization formula:
 *   M = P · r / (1 − (1 + r)^−n)
 * where M = monthly payment, P = principal, r = monthly rate, n = months.
 *
 * Edge cases:
 *   - r === 0: payment is just principal / n
 *   - n <= 0: throws (caller is responsible for input validation)
 */

export interface LoanInput {
  principal: number
  annualRatePct: number
  years: number
}

export interface LoanScheduleEntry {
  month: number
  payment: number
  principalPaid: number
  interestPaid: number
  remaining: number
}

export interface LoanSummary {
  monthlyPayment: number
  totalPaid: number
  totalInterest: number
  schedule: LoanScheduleEntry[]
}

export function calculateLoan({ principal, annualRatePct, years }: LoanInput): LoanSummary {
  if (principal <= 0 || years <= 0) {
    return { monthlyPayment: 0, totalPaid: 0, totalInterest: 0, schedule: [] }
  }
  const n = Math.round(years * 12)
  const r = annualRatePct / 100 / 12
  const monthlyPayment = r === 0 ? principal / n : (principal * r) / (1 - (1 + r) ** -n)

  const schedule: LoanScheduleEntry[] = []
  let remaining = principal
  for (let month = 1; month <= n; month++) {
    const interestPaid = remaining * r
    const principalPaid = monthlyPayment - interestPaid
    remaining = Math.max(0, remaining - principalPaid)
    schedule.push({ month, payment: monthlyPayment, principalPaid, interestPaid, remaining })
  }
  const totalPaid = monthlyPayment * n
  return {
    monthlyPayment,
    totalPaid,
    totalInterest: totalPaid - principal,
    schedule,
  }
}
