import type { GoalProjection } from '../types/db'

export interface GoalProjectionInput {
  /** Current invested value. */
  currentValue: number
  /** Money added every month (the DCA). */
  monthlyContribution: number
  /** Assumed annual return, e.g. 7 for 7%/yr. */
  annualReturnPct: number
  /** Target amount, e.g. 100000. */
  target: number
}

/** Cap the simulation at 100 years so an unreachable target terminates. */
const MAX_MONTHS = 1200

/**
 * Month-by-month forward simulation of an invested value growing by a monthly
 * compounding rate plus a fixed monthly contribution, until it reaches `target`.
 * Pure + deterministic; pass `now` for a stable reach date in tests.
 *
 * `contributed` = current value + all contributions paid in by the reach date
 * ("ce que tu as versé"); `marketGrowth` = target − contributed
 * ("ce que le marché a fait") — the same split the user cares about.
 */
export function projectGoal(input: GoalProjectionInput, now: Date = new Date()): GoalProjection {
  const { currentValue, monthlyContribution, annualReturnPct, target } = input
  const monthlyRate = (1 + annualReturnPct / 100) ** (1 / 12) - 1

  let months: number | null = null
  if (currentValue >= target) {
    months = 0
  } else {
    let value = currentValue
    for (let m = 1; m <= MAX_MONTHS; m++) {
      value = value * (1 + monthlyRate) + monthlyContribution
      if (value >= target) {
        months = m
        break
      }
    }
  }

  if (months === null) {
    return {
      target,
      currentValue,
      monthlyContribution,
      annualReturnPct,
      monthsToReach: null,
      reachDateIso: null,
      contributed: 0,
      marketGrowth: 0,
    }
  }

  const reachDate = new Date(
    Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + months, now.getUTCDate()),
  )
  const contributed = currentValue + monthlyContribution * months
  const marketGrowth = Math.max(0, target - contributed)
  return {
    target,
    currentValue,
    monthlyContribution,
    annualReturnPct,
    monthsToReach: months,
    reachDateIso: reachDate.toISOString().slice(0, 10),
    contributed,
    marketGrowth,
  }
}
