/**
 * Compound interest helpers — pure functions, no I/O.
 *
 * Formula:
 *   FV = P · (1 + r/m)^(m·t) + PMT · ((1 + r/m)^(m·t) − 1) / (r/m)
 * where P = initial deposit, PMT = recurring contribution per compounding
 * period, r = annual rate, m = compoundings per year, t = years.
 *
 * To keep the chart simple we always show monthly granularity (m=12) and
 * convert any user-supplied "annual contribution" to its monthly equivalent.
 */

export interface CompoundInput {
  initial: number
  monthlyContribution: number
  annualRatePct: number
  years: number
}

export interface CompoundPoint {
  month: number
  contributed: number
  balance: number
  /** Pure compounding contribution (excludes principal + deposits). */
  interest: number
}

export interface CompoundSummary {
  finalBalance: number
  totalContributed: number
  totalInterest: number
  series: CompoundPoint[]
}

export function calculateCompound({
  initial,
  monthlyContribution,
  annualRatePct,
  years,
}: CompoundInput): CompoundSummary {
  if (years <= 0) {
    return {
      finalBalance: initial,
      totalContributed: initial,
      totalInterest: 0,
      series: [{ month: 0, contributed: initial, balance: initial, interest: 0 }],
    }
  }
  const months = Math.round(years * 12)
  const r = annualRatePct / 100 / 12
  let balance = initial
  let contributed = initial
  const series: CompoundPoint[] = [{ month: 0, contributed, balance, interest: 0 }]
  for (let month = 1; month <= months; month++) {
    // Interest on the running balance, then deposit at end-of-month.
    balance = balance * (1 + r) + monthlyContribution
    contributed += monthlyContribution
    series.push({
      month,
      contributed,
      balance,
      interest: balance - contributed,
    })
  }
  const finalBalance = series[series.length - 1]?.balance ?? initial
  return {
    finalBalance,
    totalContributed: contributed,
    totalInterest: finalBalance - contributed,
    series,
  }
}
