import { describe, expect, it } from 'vitest'
import { createSqliteMutations } from '@florin/db-sqlite/actions'
import { materializeScheduledTransactions, recomputeAccountBalance } from '@florin/db-sqlite/actions'
// nextMonthlyOccurrenceAfter + clampDay are pure helpers not on the exports map.
import { nextMonthlyOccurrenceAfter } from '../../../../packages/db-sqlite/src/actions/recurring'
import { ID, makeForecastDb, readBalance, seedAccount } from './forecast-test-helpers'

interface SchedRow {
  id: string
  account_id: string
  occurred_at: string
  amount: number
  status: string
  transfer_pair_id: string | null
  recurrence_key: string | null
}

function scheduledRows(raw: ReturnType<typeof makeForecastDb>['raw']): SchedRow[] {
  return raw
    .prepare(
      `SELECT id, account_id, occurred_at, amount, status, transfer_pair_id, recurrence_key
       FROM transactions WHERE status = 'scheduled' AND deleted_at IS NULL
       ORDER BY occurred_at, amount`,
    )
    .all() as SchedRow[]
}

describe('nextMonthlyOccurrenceAfter', () => {
  it('returns Aug 2 for (July 2, dayOfMonth=2) — strictly after', () => {
    const result = nextMonthlyOccurrenceAfter(new Date(Date.UTC(2026, 6, 2)), 2) // July 2 2026
    expect(result.toISOString().slice(0, 10)).toBe('2026-08-02')
  })

  it('clamps day 31 to the last day of a short month', () => {
    // After Jan 15, dayOfMonth=31 → Jan 31 (still after Jan 15).
    const jan = nextMonthlyOccurrenceAfter(new Date(Date.UTC(2026, 0, 15)), 31)
    expect(jan.toISOString().slice(0, 10)).toBe('2026-01-31')
    // After Jan 31, dayOfMonth=31 → Feb 28 (2026 is not a leap year).
    const feb = nextMonthlyOccurrenceAfter(new Date(Date.UTC(2026, 0, 31)), 31)
    expect(feb.toISOString().slice(0, 10)).toBe('2026-02-28')
  })
})

describe('materializeScheduledTransactions — monthly transfer rule', () => {
  it('generates paired scheduled legs within the 3-month horizon, idempotent on re-run', async () => {
    const ctx = makeForecastDb()
    const mutations = createSqliteMutations(ctx.db)
    seedAccount(ctx, { id: ID.accountChecking, name: 'CCP' })
    seedAccount(ctx, { id: ID.accountSavings, name: 'PEA' })

    // Rule starting 2 months ago so the lower bound is "today".
    const start = new Date(Date.now() - 60 * 86_400_000)
    const created = await mutations.createRecurringRule({
      name: 'DCA PEA',
      kind: 'transfer',
      accountId: ID.accountChecking,
      toAccountId: ID.accountSavings,
      amount: 500,
      frequency: 'monthly',
      dayOfMonth: 15,
      startDate: start,
    })
    expect(created.success).toBe(true)

    const first = await materializeScheduledTransactions(ctx.db)
    expect(first.success).toBe(true)
    expect(first.data!.generated).toBeGreaterThan(0)

    const rows = scheduledRows(ctx.raw)
    expect(rows.length).toBeGreaterThan(0)
    // Even number of legs (every occurrence is a pair).
    expect(rows.length % 2).toBe(0)

    // All rows: scheduled, carry a recurrenceKey, and on day 15.
    for (const r of rows) {
      expect(r.status).toBe('scheduled')
      expect(r.recurrence_key).toBeTruthy()
      expect(r.transfer_pair_id).toBeTruthy()
      expect(r.occurred_at.slice(8, 10)).toBe('15')
    }

    // Each occurrence is a balanced pair: one -500 on CCP, one +500 on PEA,
    // sharing transferPairId + recurrenceKey.
    const byKey = new Map<string, SchedRow[]>()
    for (const r of rows) {
      const k = r.recurrence_key as string
      byKey.set(k, [...(byKey.get(k) ?? []), r])
    }
    for (const [, legs] of byKey) {
      expect(legs.length).toBe(2)
      expect(legs[0].transfer_pair_id).toBe(legs[1].transfer_pair_id)
      const amounts = legs.map((l) => l.amount).sort((a, b) => a - b)
      expect(amounts).toEqual([-500, 500])
      const out = legs.find((l) => l.amount === -500)!
      const inc = legs.find((l) => l.amount === 500)!
      expect(out.account_id).toBe(ID.accountChecking)
      expect(inc.account_id).toBe(ID.accountSavings)
    }

    // Idempotency: re-running generates nothing new (recurrence_key unique).
    const second = await materializeScheduledTransactions(ctx.db)
    expect(second.success).toBe(true)
    expect(second.data!.generated).toBe(0)
    expect(scheduledRows(ctx.raw).length).toBe(rows.length)

    // Scheduled rows do not move the realized balance.
    await recomputeAccountBalance(ctx.db, ID.accountChecking)
    expect(readBalance(ctx, ID.accountChecking)).toBe(0)
  })

  it('day-31 rule clamps to month end across short months', async () => {
    const ctx = makeForecastDb()
    const mutations = createSqliteMutations(ctx.db)
    seedAccount(ctx, { id: ID.accountChecking })

    const start = new Date(Date.now() - 90 * 86_400_000)
    await mutations.createRecurringRule({
      name: 'Rent',
      kind: 'transaction',
      accountId: ID.accountChecking,
      amount: 1000,
      frequency: 'monthly',
      dayOfMonth: 31,
      startDate: start,
    })

    await materializeScheduledTransactions(ctx.db)

    const days = (
      ctx.raw
        .prepare("SELECT occurred_at FROM transactions WHERE status = 'scheduled'")
        .all() as { occurred_at: string }[]
    ).map((r) => r.occurred_at)

    expect(days.length).toBeGreaterThan(0)
    // Every materialized day must be a valid day that is the rule's day clamped
    // to that month's last day — i.e. it never produces an invalid date like 02-31.
    for (const iso of days) {
      const [y, m, d] = iso.split('-').map(Number)
      const lastDay = new Date(Date.UTC(y, m, 0)).getUTCDate()
      // dayOfMonth=31 clamps to min(31, lastDay) = lastDay for every month.
      expect(d).toBe(lastDay)
    }
  })

  it('an inactive rule generates nothing', async () => {
    const ctx = makeForecastDb()
    const mutations = createSqliteMutations(ctx.db)
    seedAccount(ctx, { id: ID.accountChecking })
    const created = await mutations.createRecurringRule({
      name: 'Paused',
      kind: 'transaction',
      accountId: ID.accountChecking,
      amount: 100,
      frequency: 'monthly',
      dayOfMonth: 10,
      startDate: new Date(Date.now() - 40 * 86_400_000),
    })
    await mutations.updateRecurringRule({ id: created.data!.id, isActive: false })

    const res = await materializeScheduledTransactions(ctx.db)
    expect(res.success).toBe(true)
    expect(res.data!.generated).toBe(0)
    expect(scheduledRows(ctx.raw).length).toBe(0)
  })
})
