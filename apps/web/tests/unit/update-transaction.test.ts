import { describe, expect, it } from 'vitest'
import { createSqliteMutations } from '@florin/db-sqlite/actions'
import {
  makeForecastDb,
  seedAccount,
  seedTx,
  readBalance,
  isoOffsetDays,
  todayIso,
} from './forecast-test-helpers'

// updateTransaction: manual correction of date / amount / payee, with balance
// re-derivation. Primary use case: repositioning a reimbursement onto the day
// of the shared expense so a single day isn't over-counted.
describe('updateTransaction', () => {
  it('moves a transaction date without touching the balance (same realized bucket)', async () => {
    const ctx = makeForecastDb()
    const acc = seedAccount(ctx, { openingBalance: 0, currentBalance: 0 })
    // A 300 € expense 5 days ago + a 225 € reimbursement 2 days ago.
    seedTx(ctx, { accountId: acc, occurredAt: isoOffsetDays(-5), amount: -300, payee: 'Group dinner' })
    const reimb = seedTx(ctx, { accountId: acc, occurredAt: isoOffsetDays(-2), amount: 225, payee: 'Refund' })
    const m = createSqliteMutations(ctx.db)

    const before = readBalance(ctx, acc)
    const res = await m.updateTransaction(reimb, { occurredAt: new Date(`${isoOffsetDays(-5)}T00:00:00`) })
    expect(res.success).toBe(true)
    // Net balance unchanged — both dates are past+cleared, only the day moved.
    expect(readBalance(ctx, acc)).toBeCloseTo(before, 2)

    const row = ctx.raw.prepare('SELECT occurred_at AS d FROM transactions WHERE id = ?').get(reimb) as { d: string }
    expect(row.d).toBe(isoOffsetDays(-5))
  })

  it('edits the amount and adjusts the balance by the difference', async () => {
    const ctx = makeForecastDb()
    const acc = seedAccount(ctx, { openingBalance: 0, currentBalance: -100 })
    const tx = seedTx(ctx, { accountId: acc, occurredAt: todayIso(), amount: -100, payee: 'Bar' })
    const m = createSqliteMutations(ctx.db)

    const res = await m.updateTransaction(tx, { amount: -40 })
    expect(res.success).toBe(true)
    // Local ledger recomputes from scratch: opening 0 + (-40) = -40.
    expect(readBalance(ctx, acc)).toBeCloseTo(-40, 2)
  })

  it('re-derives status to scheduled when moved to the future (drops from realized balance)', async () => {
    const ctx = makeForecastDb()
    const acc = seedAccount(ctx, { openingBalance: 0, currentBalance: -50 })
    const tx = seedTx(ctx, { accountId: acc, occurredAt: todayIso(), amount: -50, status: 'cleared' })
    const m = createSqliteMutations(ctx.db)

    await m.updateTransaction(tx, { occurredAt: new Date(`${isoOffsetDays(10)}T00:00:00`) })
    const row = ctx.raw.prepare('SELECT status AS s FROM transactions WHERE id = ?').get(tx) as { s: string }
    expect(row.s).toBe('scheduled')
    // Future scheduled row no longer counts toward the realized balance.
    expect(readBalance(ctx, acc)).toBeCloseTo(0, 2)
  })

  it('updates payee + normalized payee and rejects an empty patch', async () => {
    const ctx = makeForecastDb()
    const acc = seedAccount(ctx)
    const tx = seedTx(ctx, { accountId: acc, occurredAt: todayIso(), amount: -10, payee: 'old' })
    const m = createSqliteMutations(ctx.db)

    expect((await m.updateTransaction(tx, {})).success).toBe(false)

    const ok = await m.updateTransaction(tx, { payee: 'Chez Bob' })
    expect(ok.success).toBe(true)
    const row = ctx.raw
      .prepare('SELECT payee AS p, normalized_payee AS n FROM transactions WHERE id = ?')
      .get(tx) as { p: string; n: string }
    expect(row.p).toBe('Chez Bob')
    expect(row.n.length).toBeGreaterThan(0)
  })
})
