import type { PatrimonyPoint } from '../../../types'
import type { SparkPoint } from '../primitives/sparkline'

export type Range = '1m' | '3m' | '6m' | '1y' | 'all'

export const RANGES: ReadonlyArray<{ value: Range; key: string; fallback: string; days: number }> = [
  { value: '1m', key: 'v2.range.1m', fallback: '1M', days: 31 },
  { value: '3m', key: 'v2.range.3m', fallback: '3M', days: 92 },
  { value: '6m', key: 'v2.range.6m', fallback: '6M', days: 183 },
  { value: '1y', key: 'v2.range.1y', fallback: '1Y', days: 366 },
  { value: 'all', key: 'v2.range.all', fallback: 'All', days: Number.POSITIVE_INFINITY },
]

/**
 * Even-stride downsample that always keeps the first and last sample.
 *
 * `getPatrimonyTimeSeries` returns one point per *day*, so "all history" on a
 * five-year-old install is ~1 800 objects crossing the RSC boundary for a
 * 350px-wide chart. Dropping to `max` points is invisible at that width and
 * cuts the payload by an order of magnitude — but the last point must survive
 * verbatim, because it is the number the hero prints.
 */
export function downsample<T>(points: T[], max: number): T[] {
  if (points.length <= max || max < 2) return points
  const stride = (points.length - 1) / (max - 1)
  const out: T[] = []
  for (let i = 0; i < max - 1; i++) out.push(points[Math.round(i * stride)]!)
  out.push(points[points.length - 1]!)
  return out
}

/** Trim a daily series to the trailing window a range asks for. */
export function sliceRange(points: PatrimonyPoint[], range: Range): PatrimonyPoint[] {
  const spec = RANGES.find((r) => r.value === range)
  if (!spec || !Number.isFinite(spec.days) || points.length === 0) return points
  const last = points[points.length - 1]
  const end = last ? new Date(last.date).getTime() : Date.now()
  const from = end - spec.days * 86_400_000
  const sliced = points.filter((p) => new Date(p.date).getTime() >= from)
  // A window shorter than two samples has nothing to draw — fall back rather
  // than render a single dot the user cannot scrub.
  return sliced.length >= 2 ? sliced : points.slice(-2)
}

export function toSparkPoints(points: PatrimonyPoint[]): SparkPoint[] {
  return points.map((p) => ({
    x: new Date(p.date).getTime(),
    y: p.balance,
    projected: p.projected,
    label: p.date,
  }))
}

/**
 * Drop the flat run at the head of a back-walked series.
 *
 * `getPatrimonyTimeSeries(n)` always emits one point per day for the whole n
 * months, even for the stretch before the first transaction exists — the walk
 * simply has nothing to subtract, so it emits the same balance over and over.
 * Asking for "all history" therefore draws a long dead-flat prefix that makes
 * the real curve look like a cliff at the end. Trimming it (keeping one point
 * so the line still starts at the correct level) is what makes the "All" range
 * honest.
 */
export function trimLeadingFlat(points: PatrimonyPoint[]): PatrimonyPoint[] {
  if (points.length < 3) return points
  const first = points[0]!.balance
  let i = 0
  while (i < points.length - 1 && points[i + 1]!.balance === first) i++
  return i === 0 ? points : points.slice(i)
}
