import { randomUUID } from 'node:crypto'
import { describe, expect, it } from 'vitest'
import { recomputeAccountBalance } from '@florin/db-sqlite/actions'
import { getNetWorth } from '@florin/db-sqlite'
// These query functions are not surfaced through the package exports map, so we
// import them straight from source (Vite resolves relative file paths directly).
import {
  getProjectedNetWorth,
  getPatrimonyTimeSeries,
  getScheduledDeltaByAccount,
} from '../../../../packages/db-sqlite/src/queries/dashboard'
import {
  isoOffsetDays,
  makeForecastDb,
  readBalance,
  seedAccount,
  seedTx,
  todayIso,
} from './forecast-test-helpers'

describe('recomputeAccountBalance — realized filter', () => {
  it('excludes scheduled future + cleared future rows (opening 1000 + cleared past 100 → 1100)', async () => {
    const ctx = makeForecastDb()
    const accId = seedAccount(ctx, { openingBalance: 1000, currentBalance: 0 })

    // cleared, past → counts
    seedTx(ctx, { accountId: accId, occurredAt: isoOffsetDays(-5), amount: 100, status: 'cleared' })
    // scheduled, future → excluded (status)
    seedTx(ctx, { accountId: accId, occurredAt: isoOffsetDays(10), amount: 500, status: 'scheduled' })
    // cleared, FUTURE-dated → excluded (date predicate)
    seedTx(ctx, { accountId: accId, occurredAt: isoOffsetDays(10), amount: 200, status: 'cleared' })

    await recomputeAccountBalance(ctx.db, accId)

    expect(readBalance(ctx, accId)).toBe(1100)
  })

  it('counts a cleared tx dated exactly today', async () => {
    const ctx = makeForecastDb()
    const accId = seedAccount(ctx, { openingBalance: 0 })
    seedTx(ctx, { accountId: accId, occurredAt: todayIso(), amount: 42, status: 'cleared' })

    await recomputeAccountBalance(ctx.db, accId)

    expect(readBalance(ctx, accId)).toBe(42)
  })

  it('bank-synced account: scheduled/future rows never move balance; only explicit delta does', async () => {
    const ctx = makeForecastDb()
    const accId = seedAccount(ctx, {
      openingBalance: 0,
      currentBalance: 5000,
      syncProvider: 'enable_banking',
    })
    // Ledger rows must be ignored for bank-synced accounts.
    seedTx(ctx, { accountId: accId, occurredAt: isoOffsetDays(-1), amount: 100, status: 'cleared' })
    seedTx(ctx, { accountId: accId, occurredAt: isoOffsetDays(5), amount: 500, status: 'scheduled' })

    await recomputeAccountBalance(ctx.db, accId)
    expect(readBalance(ctx, accId)).toBe(5000) // unchanged, no delta

    await recomputeAccountBalance(ctx.db, accId, 250)
    expect(readBalance(ctx, accId)).toBe(5250) // moved by explicit delta only
  })
})

describe('getNetWorth / getProjectedNetWorth', () => {
  it('getNetWorth returns realized net; getProjectedNetWorth adds scheduled-within-horizon', async () => {
    const ctx = makeForecastDb()
    const accId = seedAccount(ctx, { openingBalance: 1000 })
    // realized cleared past
    seedTx(ctx, { accountId: accId, occurredAt: isoOffsetDays(-3), amount: 200, status: 'cleared' })
    await recomputeAccountBalance(ctx.db, accId) // currentBalance = 1200

    // scheduled within the 90d horizon (+300) and one beyond it (+999, day 200)
    seedTx(ctx, { accountId: accId, occurredAt: isoOffsetDays(20), amount: 300, status: 'scheduled' })
    seedTx(ctx, { accountId: accId, occurredAt: isoOffsetDays(200), amount: 999, status: 'scheduled' })

    const nw = await getNetWorth(ctx.db)
    expect(nw.net).toBe(1200)

    const projected = await getProjectedNetWorth(ctx.db, 90)
    expect(projected.scheduledDelta).toBe(300) // only within-horizon row
    expect(projected.projected).toBe(1500)
  })

  it('transfer legs net to 0 in projected net worth (paired scheduled legs cancel)', async () => {
    const ctx = makeForecastDb()
    const from = seedAccount(ctx, { id: undefined, name: 'CCP', openingBalance: 1000 })
    const to = seedAccount(ctx, { name: 'PEA', openingBalance: 0 })
    await recomputeAccountBalance(ctx.db, from)
    await recomputeAccountBalance(ctx.db, to)

    const pairId = randomUUID()
    seedTx(ctx, {
      accountId: from,
      occurredAt: isoOffsetDays(10),
      amount: -500,
      status: 'scheduled',
      transferPairId: pairId,
    })
    seedTx(ctx, {
      accountId: to,
      occurredAt: isoOffsetDays(10),
      amount: 500,
      status: 'scheduled',
      transferPairId: pairId,
    })

    const projected = await getProjectedNetWorth(ctx.db, 90)
    // Transfer legs are excluded entirely (transferPairId IS NULL filter) → net 0 contribution.
    expect(projected.scheduledDelta).toBe(0)
    expect(projected.projected).toBe(1000)
  })
})

describe('getScheduledDeltaByAccount', () => {
  it('sums scheduled + future rows per account', async () => {
    const ctx = makeForecastDb()
    const a = seedAccount(ctx, { name: 'A' })
    const b = seedAccount(ctx, { name: 'B' })
    seedTx(ctx, { accountId: a, occurredAt: isoOffsetDays(5), amount: 100, status: 'scheduled' })
    seedTx(ctx, { accountId: a, occurredAt: isoOffsetDays(8), amount: 50, status: 'scheduled' })
    seedTx(ctx, { accountId: b, occurredAt: isoOffsetDays(2), amount: 999, status: 'cleared' }) // future-dated cleared
    // a realized past row should not be counted
    seedTx(ctx, { accountId: a, occurredAt: isoOffsetDays(-2), amount: 777, status: 'cleared' })

    const map = await getScheduledDeltaByAccount(ctx.db)
    expect(map[a]).toBe(150)
    expect(map[b]).toBe(999)
  })
})

describe('getPatrimonyTimeSeries — future-scheduled regression', () => {
  it('adding a future scheduled tx does NOT change any past point and is excluded from today', async () => {
    const ctx = makeForecastDb()
    const accId = seedAccount(ctx, { openingBalance: 1000 })
    // Two realized rows in the recent past.
    seedTx(ctx, { accountId: accId, occurredAt: isoOffsetDays(-40), amount: 100, status: 'cleared' })
    seedTx(ctx, { accountId: accId, occurredAt: isoOffsetDays(-10), amount: 200, status: 'cleared' })
    await recomputeAccountBalance(ctx.db, accId) // realized net = 1300

    const before = await getPatrimonyTimeSeries(ctx.db, 12)
    const todayPointBefore = before[before.length - 1]
    expect(todayPointBefore.balance).toBe(1300)

    // Now add a large scheduled future tx and a future-dated cleared tx.
    seedTx(ctx, { accountId: accId, occurredAt: isoOffsetDays(15), amount: 5000, status: 'scheduled' })
    seedTx(ctx, { accountId: accId, occurredAt: isoOffsetDays(20), amount: 7000, status: 'cleared' })

    const after = await getPatrimonyTimeSeries(ctx.db, 12)

    // Same number of points, and every point's balance is byte-for-byte identical.
    expect(after.length).toBe(before.length)
    for (let i = 0; i < before.length; i++) {
      expect(after[i].date).toBe(before[i].date)
      expect(after[i].balance).toBe(before[i].balance)
    }
    // The "today" anchor still reflects only realized money.
    expect(after[after.length - 1].balance).toBe(1300)
  })
})
