import type { SubscriptionMatch } from '../../types/index'

export interface SubRow {
  payee: string | null
  amount: number
  occurredAt: string
  categoryName: string | null
}

/**
 * Detect recurring subscription charges in a list of negative transactions.
 *
 * Groups rows by (normalizedPayee, rounded amount to the euro) because merchant
 * names vary slightly per posting and prices often drift a cent or two. A
 * group counts as a subscription if it has ≥3 samples AND every gap between
 * consecutive occurrences is either 30±7 days (monthly) or 7±2 days (weekly).
 * Annual cost assumes the pattern continues for a full year.
 */
export function detectSubscriptions(rows: ReadonlyArray<SubRow>): SubscriptionMatch[] {
  const buckets = new Map<string, SubRow[]>()
  for (const r of rows) {
    if (!r.payee) continue
    const key = `${r.payee}|${Math.round(r.amount)}`
    const arr = buckets.get(key) ?? []
    arr.push(r)
    buckets.set(key, arr)
  }

  const out: SubscriptionMatch[] = []
  for (const items of buckets.values()) {
    if (items.length < 3) continue
    const sorted = [...items].sort(
      (a, b) => new Date(a.occurredAt).getTime() - new Date(b.occurredAt).getTime(),
    )
    const gaps: number[] = []
    for (let i = 1; i < sorted.length; i += 1) {
      const prev = new Date(sorted[i - 1]!.occurredAt).getTime()
      const curr = new Date(sorted[i]!.occurredAt).getTime()
      gaps.push(Math.round((curr - prev) / (24 * 60 * 60 * 1000)))
    }
    const avg = gaps.reduce((a, b) => a + b, 0) / gaps.length
    const isMonthly = gaps.every((g) => Math.abs(g - 30) <= 7)
    const isWeekly = gaps.every((g) => Math.abs(g - 7) <= 2)
    if (!isMonthly && !isWeekly) continue

    const cadenceDays = isMonthly ? 30 : 7
    const last = sorted[sorted.length - 1]!
    const amount = last.amount
    out.push({
      payee: last.payee ?? '(unknown)',
      amount,
      cadenceDays: Math.round(avg),
      samples: items.length,
      lastSeen: last.occurredAt.slice(0, 10),
      annualCost: Math.abs(amount) * (365 / cadenceDays),
      categoryName: last.categoryName,
    })
  }
  return out.sort((a, b) => b.annualCost - a.annualCost)
}
