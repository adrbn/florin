/**
 * Loan liability helper.
 *
 * The naive way to compute a loan's remaining debt is
 * `originalPrincipal − totalPaid`, but that ignores interest accrual — after
 * 22 × 135,91 € payments on a 10 000 € / 3.9 % / 84 months loan it gives
 * ~7 010 € when the bank actually says 7 645 €. Over multi-year loans this
 * gap grows to hundreds of euros.
 *
 * The correct value is `schedule.rows[paymentsMade - 1].balanceAfter` from
 * a standard amortization walk. This module centralizes that math so every
 * view (account detail tiles, dashboard net worth KPI, patrimony chart
 * anchor, reflect time series, accounts grouped list) reports the same
 * number — the same number the bank shows on its capital restant dû line.
 *
 * The amortization math itself lives in `./amortization`; this file adds
 * (1) an adapter from the DB's `accounts` row shape to `LoanInputs`,
 * (2) a principal/interest split of the money paid so far, and
 * (3) a graceful fallback when loan params aren't configured yet.
 */

import { computeTermMonths, type LoanInputs, simulateSchedule } from './amortization'

/**
 * Shape we need from an account row. Kept structural (not pulled from Drizzle
 * inferred types) so both the server queries and the client pages can share
 * the same helper without dragging the full account schema into the client
 * bundle.
 */
export interface LoanAccountFields {
  kind: string
  loanOriginalPrincipal: string | number | null
  loanInterestRate: string | number | null
  loanTermMonths: number | null
  loanMonthlyPayment: string | number | null
  loanStartDate: Date | string | null
  /**
   * Optional raw account balance, used as a fallback when the loan params
   * aren't fully configured yet. If both the schedule build and this field
   * are unavailable, liability reverts to 0.
   */
  currentBalance?: string | number | null
}

export interface LoanLiability {
  /** Capital restant dû (positive number). */
  remainingDebt: number
  /** Principal portion of the money paid so far. */
  principalPaid: number
  /** Interest portion of the money paid so far. */
  interestPaid: number
  /**
   * True when the number was derived from the amortization schedule; false
   * when it fell back to `principal − totalPaid` or to the account balance
   * because loan parameters were incomplete.
   */
  fromSchedule: boolean
}

function toNumber(v: string | number | null | undefined): number {
  if (v === null || v === undefined || v === '') return 0
  const n = typeof v === 'number' ? v : Number(v)
  return Number.isFinite(n) ? n : 0
}

/**
 * Compute the liability breakdown for a single loan account after
 * `paymentsMade` mensualités. Pure function — no DB access, no React deps.
 *
 * When the loan has all four core parameters (principal, rate, term OR
 * monthly payment, start date), walks the amortization schedule to row
 * `paymentsMade − 1` and returns `{ remainingDebt: balanceAfter, ... }`.
 *
 * Otherwise falls back to:
 *   1. `principal − totalPaidFallback` if we have at least the principal
 *      (mirrors the legacy behaviour for loans that haven't been fully
 *      configured yet),
 *   2. `|currentBalance|` if we don't even have a principal (assumes the
 *      user is using the raw account balance as the liability).
 */
export function computeLoanLiability(
  account: LoanAccountFields,
  paymentsMade: number,
  totalPaidFallback = 0,
): LoanLiability {
  const principal = toNumber(account.loanOriginalPrincipal)
  const annualRate = toNumber(account.loanInterestRate)
  const monthlyPayment = toNumber(account.loanMonthlyPayment)
  const start = account.loanStartDate ? new Date(account.loanStartDate) : null

  // Fallback chain — used whenever the amortization inputs are too
  // incomplete to build a schedule.
  const naiveFallback = (): LoanLiability => {
    if (principal > 0) {
      return {
        remainingDebt: Math.max(0, principal - totalPaidFallback),
        principalPaid: totalPaidFallback,
        interestPaid: 0,
        fromSchedule: false,
      }
    }
    // No principal configured — use |currentBalance| as a last resort so
    // a barely-set-up loan still pulls net worth down by roughly the right
    // amount instead of vanishing entirely.
    return {
      remainingDebt: Math.abs(toNumber(account.currentBalance)),
      principalPaid: 0,
      interestPaid: 0,
      fromSchedule: false,
    }
  }

  if (principal <= 0 || annualRate < 0) return naiveFallback()
  if (!start || Number.isNaN(start.getTime())) return naiveFallback()

  let term = account.loanTermMonths && account.loanTermMonths > 0 ? account.loanTermMonths : 0
  if (term <= 0) {
    if (monthlyPayment <= 0) return naiveFallback()
    const derived = computeTermMonths({
      originalPrincipal: principal,
      annualRate,
      monthlyPayment,
    })
    if (!derived) return naiveFallback()
    term = derived
  }

  const loanInputs: LoanInputs = {
    originalPrincipal: principal,
    annualRate,
    termMonths: term,
    startDate: start,
  }

  // Use the stored mensualité as the override when it's set — banks round
  // the payment differently from our formula (135.91 € vs 136.30 € on the
  // user's Prêt étudiant, ~15 € of balance drift after 2 years).
  const baseMonthlyPayment = monthlyPayment > 0 ? monthlyPayment : undefined
  const schedule = simulateSchedule(loanInputs, { baseMonthlyPayment })

  if (paymentsMade <= 0) {
    return {
      remainingDebt: principal,
      principalPaid: 0,
      interestPaid: 0,
      fromSchedule: true,
    }
  }

  // Clamp the cursor to the schedule length. If the user has somehow
  // applied more mensualités than the contract lists the schedule already
  // ends at balance 0 — just read the tail.
  const cursor = Math.min(paymentsMade, schedule.rows.length) - 1
  const row = schedule.rows[cursor]
  if (!row) return naiveFallback()

  const paidRows = schedule.rows.slice(0, cursor + 1)
  const principalPaid = paidRows.reduce((sum, r) => sum + r.principal + r.extraPayment, 0)
  const interestPaid = paidRows.reduce((sum, r) => sum + r.interest, 0)

  return {
    remainingDebt: Math.max(0, row.balanceAfter),
    principalPaid,
    interestPaid,
    fromSchedule: true,
  }
}
