/**
 * Loan amortization math.
 *
 * Given the four standard inputs the user fills in on the loan settings form
 * (original principal, annual rate, term in months, start date) we produce:
 *   - a monthly "what you pay" schedule showing principal/interest split
 *   - the theoretical fixed monthly payment (mensualité)
 *   - a helper that simulates early repayments and reports months saved
 *     and interest saved vs the base schedule
 *
 * Everything here is pure and side-effect-free — easy to unit test, no
 * dependency on the rest of the app. The UI imports these and renders
 * whatever views it wants.
 */

export interface LoanInputs {
  /** Original principal borrowed, in the account currency. */
  originalPrincipal: number
  /** Annual interest rate as a decimal. 3.5% → 0.035. */
  annualRate: number
  /** Total number of monthly instalments in the original plan. */
  termMonths: number
  /** Date of the first instalment. Drives the month column on the schedule. */
  startDate: Date
}

export interface ScheduleRow {
  /** 1-indexed instalment number. */
  index: number
  /** Calendar date of this instalment. */
  date: Date
  /** Balance carried forward BEFORE this instalment is applied. */
  balanceBefore: number
  /** Interest portion of this instalment. */
  interest: number
  /** Principal portion of this instalment. */
  principal: number
  /** Fixed mensualité — interest + principal. */
  payment: number
  /** Extra principal repaid on top of the mensualité this month, if any. */
  extraPayment: number
  /** Remaining balance AFTER this instalment has been applied. */
  balanceAfter: number
}

export interface ScheduleSummary {
  monthlyPayment: number
  totalInterest: number
  totalPaid: number
  months: number
  endDate: Date
}

export interface SimulationResult {
  rows: ScheduleRow[]
  summary: ScheduleSummary
}

/**
 * Standard fixed-payment amortization formula:
 *   M = P · r · (1+r)^n / ((1+r)^n - 1)
 * where r = monthly rate, n = number of months. Falls back to P/n when the
 * rate is zero (0% loans exist — family, interest-free student loans, etc.).
 */
export function computeMonthlyPayment(inputs: LoanInputs): number {
  const { originalPrincipal: p, annualRate, termMonths: n } = inputs
  if (n <= 0) return 0
  const r = annualRate / 12
  if (r === 0) return p / n
  const factor = (1 + r) ** n
  return (p * r * factor) / (factor - 1)
}

/**
 * Inverse of {@link computeMonthlyPayment}: given a monthly payment, solve for
 * the number of months needed to amortize the principal.
 *
 *   n = -log(1 - P·r/M) / log(1+r)
 *
 * Returns `null` when the monthly payment is too small to ever cover the
 * interest (i.e. M ≤ P·r) — the loan would never be repaid. For a zero-rate
 * loan, simplifies to ceil(P / M). Rounds up to the next whole month.
 */
export function computeTermMonths(args: {
  originalPrincipal: number
  annualRate: number
  monthlyPayment: number
}): number | null {
  const { originalPrincipal: p, annualRate, monthlyPayment: m } = args
  if (p <= 0 || m <= 0) return null
  const r = annualRate / 12
  if (r === 0) return Math.ceil(p / m)
  // Payment too small to outpace interest → loan never amortizes.
  if (m <= p * r) return null
  const n = -Math.log(1 - (p * r) / m) / Math.log(1 + r)
  if (!Number.isFinite(n) || n <= 0) return null
  return Math.ceil(n)
}

/** Round a money value to 2 decimals to dodge floating-point noise. */
function round2(v: number): number {
  return Math.round(v * 100) / 100
}

/** Add `months` whole calendar months to a date, keeping the day-of-month. */
function addMonths(date: Date, months: number): Date {
  const d = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + months, date.getUTCDate()))
  return d
}

/**
 * Build the base amortization schedule from the user's loan parameters. No
 * extra payments — that's what {@link simulateSchedule} is for.
 *
 * We drive the loop by remaining balance rather than by instalment number
 * so the last row's principal naturally absorbs any rounding slop and the
 * final balanceAfter lands exactly at zero.
 */
export function buildSchedule(inputs: LoanInputs): SimulationResult {
  const payment = computeMonthlyPayment(inputs)
  return simulateSchedule(inputs, { baseMonthlyPayment: payment, extraPayments: {} })
}

export interface SimulationOptions {
  /**
   * The fixed mensualité to apply each month. When omitted, we compute it
   * from the inputs. Allowing override lets the UI pass the user-configured
   * value instead of ours in case they round differently.
   */
  baseMonthlyPayment?: number
  /**
   * Extra principal repayments to apply, keyed by 1-indexed month number.
   * `extraPayments[3] = 1000` means "on month 3, pay an additional 1000
   * against principal". Used by the early-repayment simulator.
   */
  extraPayments?: Record<number, number>
  /**
   * One-shot lump-sum payment applied at `lumpSumMonth`. If both lumpSum
   * and extraPayments are set, they stack.
   */
  lumpSumAmount?: number
  lumpSumMonth?: number
  /**
   * Hard-close the schedule on this 1-indexed month: when the loop reaches it
   * with a positive balance, the whole remaining principal is folded into that
   * instalment so the schedule ends exactly on the contract's term instead of
   * trailing a rounding residual into an extra month — the way a lender adjusts
   * the final payment. Leave unset for the early-repayment simulator, which is
   * allowed to finish before the term.
   */
  finalMonth?: number
}

export function simulateSchedule(
  inputs: LoanInputs,
  options: SimulationOptions = {},
): SimulationResult {
  const {
    baseMonthlyPayment = computeMonthlyPayment(inputs),
    extraPayments = {},
    lumpSumAmount = 0,
    lumpSumMonth = 0,
    finalMonth = 0,
  } = options

  const rows: ScheduleRow[] = []
  const r = inputs.annualRate / 12
  let balance = inputs.originalPrincipal
  let totalInterest = 0
  let totalPaid = 0

  // Hard cap at 2× the original term so a misconfigured simulator (e.g.
  // rate so high that interest exceeds the mensualité) can't infinite-loop.
  const maxMonths = Math.max(inputs.termMonths * 2, 1)

  for (let i = 1; i <= maxMonths; i++) {
    if (balance <= 0.005) break
    const interest = round2(balance * r)
    let principalFromPayment = round2(baseMonthlyPayment - interest)
    // If the mensualité doesn't fully cover the interest, we'd be going
    // backwards — cap principal at 0 so the simulator fails gracefully
    // rather than looping forever.
    if (principalFromPayment < 0) principalFromPayment = 0

    const extraFromTable = extraPayments[i] ?? 0
    const extraLump = i === lumpSumMonth ? lumpSumAmount : 0
    let extra = extraFromTable + extraLump
    // Don't overpay past the remaining principal.
    const maxPrincipal = balance - principalFromPayment
    if (extra > maxPrincipal) extra = Math.max(maxPrincipal, 0)

    let principal = principalFromPayment + extra
    // Final-month adjustment: if the scheduled principal would over-shoot
    // the remaining balance, trim it to land exactly on zero.
    if (principal > balance) principal = balance

    // Contractual last instalment: absorb any rounding residual so the loan
    // closes exactly on its term rather than trailing a few cents into an
    // extra month. Only kicks in for real contracts that set finalMonth — the
    // early-repayment simulator leaves it unset and may finish sooner.
    if (finalMonth > 0 && i >= finalMonth && balance - principal > 0.005) {
      principal = balance
      extra = 0
    }

    const payment = round2(interest + principal - extra)
    const balanceBefore = round2(balance)
    balance = round2(balance - principal)
    totalInterest = round2(totalInterest + interest)
    totalPaid = round2(totalPaid + payment + extra)

    rows.push({
      index: i,
      date: addMonths(inputs.startDate, i - 1),
      balanceBefore,
      interest,
      principal: round2(principal - extra),
      payment,
      extraPayment: round2(extra),
      balanceAfter: balance,
    })

    if (balance <= 0.005) break
  }

  const lastRow = rows[rows.length - 1]
  const summary: ScheduleSummary = {
    monthlyPayment: round2(baseMonthlyPayment),
    totalInterest,
    totalPaid,
    months: rows.length,
    endDate: lastRow ? lastRow.date : inputs.startDate,
  }

  return { rows, summary }
}

/**
 * Compare two schedules and report what an early-repayment strategy actually
 * buys you. Returns absolute numbers, not percentages — the UI can format.
 */
export interface SimulationComparison {
  baseMonths: number
  newMonths: number
  monthsSaved: number
  baseInterest: number
  newInterest: number
  interestSaved: number
  baseEndDate: Date
  newEndDate: Date
}

export function compareSchedules(
  base: SimulationResult,
  simulated: SimulationResult,
): SimulationComparison {
  return {
    baseMonths: base.summary.months,
    newMonths: simulated.summary.months,
    monthsSaved: base.summary.months - simulated.summary.months,
    baseInterest: base.summary.totalInterest,
    newInterest: simulated.summary.totalInterest,
    interestSaved: round2(base.summary.totalInterest - simulated.summary.totalInterest),
    baseEndDate: base.summary.endDate,
    newEndDate: simulated.summary.endDate,
  }
}

/**
 * Recover the annual nominal rate implied by a loan's three hard numbers.
 *
 * Banks quote the TAEG (effective annual rate) but amortize on the taux
 * débiteur; users typically type the TAEG into the rate field, which makes a
 * naïve `annualRate / 12` monthly rate slightly too high and drifts our
 * "capital restant dû" a few euros above the bank's over a couple of years.
 * Given the principal, the real mensualité and the contractual term, the
 * periodic rate is fully determined — solve for it so the schedule matches the
 * lender to the cent regardless of which rate the user typed in.
 *
 * `payment(r)` is strictly increasing in `r`, so a plain bisection converges.
 * Returns the annual rate as a decimal (monthlyRate × 12), or `null` when the
 * three numbers can't describe a valid fixed-rate loan (non-positive inputs, or
 * a payment too small to ever amortize the principal).
 */
export function solveAnnualRateFromPayment(args: {
  principal: number
  monthlyPayment: number
  termMonths: number
}): number | null {
  const { principal: p, monthlyPayment: m, termMonths: n } = args
  if (!(p > 0) || !(m > 0) || !(n > 0)) return null

  const zeroRatePayment = p / n
  // At or below the 0%-loan instalment there's no positive interest to solve
  // for. Strictly below can't amortize the principal in n months at all.
  if (m <= zeroRatePayment + 1e-9) {
    return m >= zeroRatePayment - 1e-9 ? 0 : null
  }

  const paymentAt = (r: number): number => {
    if (r <= 0) return p / n
    const factor = (1 + r) ** n
    return (p * r * factor) / (factor - 1)
  }

  let lo = 0
  let hi = 1 // 100 %/month — absurdly high; guarantees paymentAt(hi) > m
  let guard = 0
  while (paymentAt(hi) < m && guard < 64) {
    hi *= 2
    guard += 1
  }
  for (let i = 0; i < 128; i += 1) {
    const mid = (lo + hi) / 2
    const pm = paymentAt(mid)
    if (Math.abs(pm - m) < 1e-11) return mid * 12
    if (pm < m) lo = mid
    else hi = mid
  }
  return ((lo + hi) / 2) * 12
}

/**
 * Return a copy of `inputs` whose `annualRate` has been recalibrated from the
 * real mensualité and term via {@link solveAnnualRateFromPayment}. Use for real
 * loan contracts where principal, payment and term are all known, so the
 * amortization matches the bank whether the user typed the TAEG or the taux
 * débiteur. No-op when the payment is missing or the numbers don't resolve to a
 * valid rate — the caller's originally-entered rate is kept unchanged.
 */
export function calibrateAnnualRate(
  inputs: LoanInputs,
  monthlyPayment: number | null | undefined,
): LoanInputs {
  if (!monthlyPayment || monthlyPayment <= 0) return inputs
  if (!(inputs.originalPrincipal > 0) || !(inputs.termMonths > 0)) return inputs
  const solved = solveAnnualRateFromPayment({
    principal: inputs.originalPrincipal,
    monthlyPayment,
    termMonths: inputs.termMonths,
  })
  if (solved === null) return inputs
  return { ...inputs, annualRate: solved }
}
