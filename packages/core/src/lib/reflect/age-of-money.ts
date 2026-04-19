/**
 * YNAB-style Age of Money.
 *
 * YNAB definition: the average age of the dollars spent across your last 10
 * outflow transactions — not a rolling weighted average over a time window.
 * This makes AoM responsive to recent behaviour instead of getting pulled
 * up forever by an old inflow still sitting in the FIFO queue.
 *
 * Algorithm (single pass over chronologically sorted transactions):
 *   - Inflows push onto a FIFO queue keyed by date.
 *   - For each outflow, pop dollars from the oldest inflow first until the
 *     outflow is covered. The outflow's "age" is the amount-weighted
 *     average of the inflow ages that funded it.
 *   - Age of Money = arithmetic mean of the ages of the last 10 outflows.
 *
 * Callers pass plain `{date, amount}` rows already filtered to on-budget
 * accounts (no loan/tracking accounts), no transfers, and no deleted rows,
 * sorted by date ascending.
 */
export interface AomTx {
  date: Date
  amount: number
}

interface Inflow {
  date: Date
  remaining: number
}

const WINDOW = 10

function outflowAge(row: AomTx, inflows: Inflow[]): number | null {
  let needed = Math.abs(row.amount)
  let weightedSum = 0
  let consumed = 0
  while (needed > 0 && inflows.length > 0) {
    const head = inflows[0]
    if (!head) break
    const take = Math.min(head.remaining, needed)
    const age = (row.date.getTime() - head.date.getTime()) / 86400000
    weightedSum += age * take
    consumed += take
    head.remaining -= take
    needed -= take
    if (head.remaining <= 0.01) inflows.shift()
  }
  if (consumed <= 0) return null
  return weightedSum / consumed
}

function averageOfLast(window: number[], n: number): number | null {
  if (window.length === 0) return null
  const slice = window.slice(-n)
  return slice.reduce((a, b) => a + b, 0) / slice.length
}

/**
 * Run the simulation across `txs` (chronological) and return the Age of
 * Money as of after the last outflow — i.e. current AoM.
 */
export function computeAgeOfMoney(txs: ReadonlyArray<AomTx>): number | null {
  const inflows: Inflow[] = []
  const ages: number[] = []
  for (const tx of txs) {
    if (tx.amount > 0) {
      inflows.push({ date: tx.date, remaining: tx.amount })
    } else if (tx.amount < 0) {
      const age = outflowAge(tx, inflows)
      if (age !== null) ages.push(age)
    }
  }
  return averageOfLast(ages, WINDOW)
}

/**
 * Age of Money value at the end of each month in the supplied range, using
 * the same FIFO + last-10 window as YNAB. The returned array is sorted
 * chronologically; each entry is `{ month: 'YYYY-MM', age: days | null }`.
 */
export interface AomHistoryPoint {
  month: string
  age: number | null
}

export function computeAgeOfMoneyHistory(
  txs: ReadonlyArray<AomTx>,
  months: ReadonlyArray<string>,
): AomHistoryPoint[] {
  // Pre-sort input to guarantee chronological order regardless of how the
  // DB returned it.
  const sorted = [...txs].sort((a, b) => a.date.getTime() - b.date.getTime())
  const inflows: Inflow[] = []
  const ages: number[] = []

  const monthEnds = months.map((m) => {
    const [y, mo] = m.split('-').map(Number)
    return {
      key: m,
      // Last instant of the month — any tx dated within this calendar month
      // should be "included" when we snapshot here.
      end: new Date(Date.UTC(y ?? 1970, (mo ?? 1), 0, 23, 59, 59, 999)),
    }
  })

  const out: AomHistoryPoint[] = []
  let txIdx = 0

  for (const { key, end } of monthEnds) {
    while (txIdx < sorted.length && sorted[txIdx]!.date.getTime() <= end.getTime()) {
      const tx = sorted[txIdx]!
      if (tx.amount > 0) {
        inflows.push({ date: tx.date, remaining: tx.amount })
      } else if (tx.amount < 0) {
        const age = outflowAge(tx, inflows)
        if (age !== null) ages.push(age)
      }
      txIdx += 1
    }
    out.push({ month: key, age: averageOfLast(ages, WINDOW) })
  }
  return out
}
