import type {
  CategorySpendingSeries,
  DailyCategorySpend,
  LeftToSpend,
  SubscriptionMatch,
} from '../../types'

/** Average days per month — converts cadences/rates to a monthly figure. */
const DAYS_PER_MONTH = 30.4368

// ────────────────────────────── Category movers ──────────────────────────────

export interface CategoryMover {
  categoryId: string
  categoryName: string
  emoji: string | null
  /** Spend in the most recent complete month. */
  current: number
  /** Spend in the month before that. */
  previous: number
  /** current − previous (positive = spending went up). */
  delta: number
  /** Percentage change, or null when `previous` was 0 (a brand-new expense). */
  pct: number | null
}

export interface CategoryMoversResult {
  currentMonth: string | null
  previousMonth: string | null
  movers: CategoryMover[]
}

/**
 * Biggest category changes between the two most recent COMPLETE months.
 *
 * The series from `getCategorySpendingSeries` always ends on the current,
 * in-progress month — comparing that half-finished month against a full one
 * would read as a giant fake "drop", so we drop it and compare the last two
 * settled months instead.
 */
export function computeCategoryMovers(
  series: CategorySpendingSeries,
  opts: { limit?: number; currentMonthInProgress?: boolean } = {},
): CategoryMoversResult {
  const { limit = 6, currentMonthInProgress = true } = opts
  const len = series.months.length
  const curIdx = currentMonthInProgress ? len - 2 : len - 1
  const prevIdx = curIdx - 1
  if (prevIdx < 0) {
    return { currentMonth: null, previousMonth: null, movers: [] }
  }

  const movers = series.categories
    .map((c) => {
      const current = c.monthly[curIdx] ?? 0
      const previous = c.monthly[prevIdx] ?? 0
      const delta = current - previous
      const pct = previous > 0 ? (delta / previous) * 100 : null
      return {
        categoryId: c.categoryId,
        categoryName: c.categoryName,
        emoji: c.emoji,
        current,
        previous,
        delta,
        pct,
      }
    })
    .filter((m) => Math.abs(m.delta) >= 1 && (m.current > 0 || m.previous > 0))
    .sort((a, b) => Math.abs(b.delta) - Math.abs(a.delta))
    .slice(0, limit)

  return {
    currentMonth: series.months[curIdx] ?? null,
    previousMonth: series.months[prevIdx] ?? null,
    movers,
  }
}

// ────────────────────────────── Month forecast ──────────────────────────────

export interface MonthForecast {
  daysElapsed: number
  daysRemaining: number
  monthSpent: number
  /** Fixed spend already paid this month (rent, loan, …) — not extrapolated. */
  fixedSpent: number
  /** Projected total spend for the month at the current daily pace. */
  projectedSpend: number
  monthIncome: number
  /** monthIncome − projectedSpend, or null when no salary is detected. */
  projectedMargin: number | null
  /** True when the projected margin is non-negative. Null without income. */
  onTrack: boolean | null
}

/**
 * Project where the month lands if the current spending pace holds.
 *
 * Only the *variable* daily pace is extrapolated forward. Fixed bills (rent,
 * loan, insurance, subscriptions — flagged `isFixed`) are big lumpy charges
 * that hit once a month; extrapolating them at a per-day rate massively
 * inflates the projection (e.g. a €1 000 rent paid on the 3rd would read as
 * "+€1 000 still coming" by mid-month). So we keep the fixed spend already
 * incurred as-is and only project the discretionary day-to-day burn.
 *
 * Margin needs a detected income for the month (a received paycheck); without
 * one we only project spend.
 */
export function computeMonthForecast(lts: LeftToSpend): MonthForecast {
  const variableSpent = Math.max(0, lts.monthSpent - lts.monthSpentFixed)
  const dailyAvgVariable = lts.daysElapsed > 0 ? variableSpent / lts.daysElapsed : 0
  const projectedSpend = lts.monthSpent + dailyAvgVariable * lts.daysRemaining
  const hasIncome = lts.monthIncome > 0
  const projectedMargin = hasIncome ? lts.monthIncome - projectedSpend : null
  return {
    daysElapsed: lts.daysElapsed,
    daysRemaining: lts.daysRemaining,
    monthSpent: lts.monthSpent,
    fixedSpent: lts.monthSpentFixed,
    projectedSpend,
    monthIncome: lts.monthIncome,
    projectedMargin,
    onTrack: projectedMargin !== null ? projectedMargin >= 0 : null,
  }
}

// ─────────────────────────── Recurring vs one-off ───────────────────────────

export interface RecurringSplit {
  /** Sum of detected subscriptions expressed as a monthly figure. */
  committedMonthly: number
  /** Average total monthly spend (the denominator). */
  totalMonthly: number
  /** max(0, total − committed). */
  discretionaryMonthly: number
  /** committed ÷ total, clamped to [0, 100]. */
  committedPct: number
  subscriptionCount: number
}

/**
 * Split average monthly spend into committed (recurring subscriptions/bills)
 * vs discretionary. Each subscription is normalised to a monthly cost via its
 * detected cadence.
 */
export function computeRecurringSplit(
  subscriptions: ReadonlyArray<SubscriptionMatch>,
  avgMonthlySpend: number,
): RecurringSplit {
  const committedMonthly = subscriptions.reduce((sum, sub) => {
    const cadence = sub.cadenceDays > 0 ? sub.cadenceDays : DAYS_PER_MONTH
    return sum + Math.abs(sub.amount) * (DAYS_PER_MONTH / cadence)
  }, 0)
  const totalMonthly = Math.max(0, avgMonthlySpend)
  const discretionaryMonthly = Math.max(0, totalMonthly - committedMonthly)
  const committedPct =
    totalMonthly > 0 ? Math.min(100, (committedMonthly / totalMonthly) * 100) : 0
  return {
    committedMonthly,
    totalMonthly,
    discretionaryMonthly,
    committedPct,
    subscriptionCount: subscriptions.length,
  }
}

// ────────────────────────────── Spending anomalies ──────────────────────────────

export interface SpendingAnomaly {
  date: string
  amount: number
  topCategoryName: string | null
  /** How many times the typical spending-day this day was. */
  multipleOfTypical: number
}

export interface SpendingAnomaliesResult {
  /** Median spend of days that had any spending — the "typical day". */
  typicalDay: number
  anomalies: SpendingAnomaly[]
}

/**
 * Flag unusually expensive days: days whose total spend is at least
 * `minMultiple`× the typical (median) spending-day and above an absolute
 * floor. Each flagged day carries the category that drove most of it.
 *
 * Fixed expenses (rent, loan, insurance, subscriptions — flagged `isFixed`)
 * are excluded by default: a day isn't "unusual" just because rent posted, so
 * counting those lumpy bills would flag every rent day and bury the genuine
 * discretionary spikes. Pass `includeFixed` to count them too.
 */
export function computeSpendingAnomalies(
  rows: ReadonlyArray<DailyCategorySpend>,
  opts: { limit?: number; minMultiple?: number; minAmount?: number; includeFixed?: boolean } = {},
): SpendingAnomaliesResult {
  const { limit = 5, minMultiple = 3, minAmount = 50, includeFixed = false } = opts
  const byDate = new Map<string, { total: number; byCat: Map<string, number> }>()
  for (const r of rows) {
    if (!includeFixed && r.isFixed) continue
    const entry = byDate.get(r.date) ?? { total: 0, byCat: new Map<string, number>() }
    entry.total += r.amount
    if (r.categoryName) {
      entry.byCat.set(r.categoryName, (entry.byCat.get(r.categoryName) ?? 0) + r.amount)
    }
    byDate.set(r.date, entry)
  }

  const totals = [...byDate.values()].map((v) => v.total).filter((v) => v > 0)
  if (totals.length === 0) {
    return { typicalDay: 0, anomalies: [] }
  }
  const typicalDay = median(totals)
  const threshold = Math.max(typicalDay * minMultiple, minAmount)

  const anomalies = [...byDate.entries()]
    .filter(([, v]) => v.total >= threshold)
    .map(([date, v]) => {
      let topName: string | null = null
      let topAmt = -1
      for (const [name, amt] of v.byCat) {
        if (amt > topAmt) {
          topAmt = amt
          topName = name
        }
      }
      return {
        date,
        amount: v.total,
        topCategoryName: topName,
        multipleOfTypical: typicalDay > 0 ? v.total / typicalDay : 0,
      }
    })
    .sort((a, b) => b.amount - a.amount)
    .slice(0, limit)

  return { typicalDay, anomalies }
}

function median(values: ReadonlyArray<number>): number {
  if (values.length === 0) return 0
  const sorted = [...values].sort((a, b) => a - b)
  const mid = Math.floor(sorted.length / 2)
  return sorted.length % 2 === 0 ? ((sorted[mid - 1]! + sorted[mid]!) / 2) : sorted[mid]!
}
