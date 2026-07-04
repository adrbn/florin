import type { PatrimonyPoint } from '../types/db'

/** Average days per month — converts a per-day slope to a monthly figure.
 * Kept in sync with the patrimony chart so the card and the chart agree. */
const DAYS_PER_MONTH = 30.4368

/**
 * Ordinary-least-squares slope of net worth over a daily patrimony series,
 * expressed per month. This is the same "une seule droite de tendance"
 * regression the patrimony chart draws — reused here so the net-worth card's
 * "+X/mois" line matches the chart exactly. Realized points only (projected
 * forecast points are excluded). Returns 0 for fewer than two points.
 *
 * x is the day index (the series is contiguous daily points, so index ≈ days),
 * mirroring the chart's day-parametrised fit.
 */
export function monthlyNetWorthTrend(points: ReadonlyArray<PatrimonyPoint>): number {
  const pts = points.filter((p) => !p.projected)
  const n = pts.length
  if (n < 2) return 0
  let sumX = 0
  let sumY = 0
  let sumXY = 0
  let sumXX = 0
  for (let i = 0; i < n; i++) {
    const x = i
    const y = pts[i]!.balance
    sumX += x
    sumY += y
    sumXY += x * y
    sumXX += x * x
  }
  const denom = n * sumXX - sumX * sumX
  if (denom === 0) return 0
  const slopePerDay = (n * sumXY - sumX * sumY) / denom
  return slopePerDay * DAYS_PER_MONTH
}
