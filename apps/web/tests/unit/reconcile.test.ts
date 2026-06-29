import { randomUUID } from 'node:crypto'
import { describe, expect, it } from 'vitest'
import { findMergeCandidateId, recomputeAccountBalance } from '@florin/db-sqlite/actions'
import { createSqliteMutations } from '@florin/db-sqlite/actions'
import {
  isoOffsetDays,
  makeForecastDb,
  readBalance,
  seedAccount,
  seedTx,
} from './forecast-test-helpers'

describe('findMergeCandidateId', () => {
  it('matches an exact-cent, within-3-days, scheduled candidate', async () => {
    const ctx = makeForecastDb()
    const accId = seedAccount(ctx)
    const candidate = seedTx(ctx, {
      accountId: accId,
      occurredAt: isoOffsetDays(0),
      amount: -42.5,
      status: 'scheduled',
    })

    const match = await findMergeCandidateId(ctx.db, {
      accountId: accId,
      amount: -42.5,
      occurredAt: isoOffsetDays(2), // 2 days off, within window
    })
    expect(match).toBe(candidate)
  })

  it('no match when amount is off by 0.02', async () => {
    const ctx = makeForecastDb()
    const accId = seedAccount(ctx)
    seedTx(ctx, { accountId: accId, occurredAt: isoOffsetDays(0), amount: -42.5, status: 'scheduled' })

    const match = await findMergeCandidateId(ctx.db, {
      accountId: accId,
      amount: -42.52,
      occurredAt: isoOffsetDays(0),
    })
    expect(match).toBeNull()
  })

  it('no match when date is off by 4 days', async () => {
    const ctx = makeForecastDb()
    const accId = seedAccount(ctx)
    seedTx(ctx, { accountId: accId, occurredAt: isoOffsetDays(0), amount: -42.5, status: 'scheduled' })

    const match = await findMergeCandidateId(ctx.db, {
      accountId: accId,
      amount: -42.5,
      occurredAt: isoOffsetDays(4),
    })
    expect(match).toBeNull()
  })

  it('no match for opposite sign', async () => {
    const ctx = makeForecastDb()
    const accId = seedAccount(ctx)
    seedTx(ctx, { accountId: accId, occurredAt: isoOffsetDays(0), amount: -42.5, status: 'scheduled' })

    const match = await findMergeCandidateId(ctx.db, {
      accountId: accId,
      amount: 42.5, // positive vs scheduled negative
      occurredAt: isoOffsetDays(0),
    })
    expect(match).toBeNull()
  })

  it('a row that already has externalId is never a candidate', async () => {
    const ctx = makeForecastDb()
    const accId = seedAccount(ctx)
    // A manual cleared row that would otherwise match, but it has an externalId.
    seedTx(ctx, {
      accountId: accId,
      occurredAt: isoOffsetDays(0),
      amount: -42.5,
      status: 'cleared',
      source: 'manual',
      externalId: 'already-imported-123',
    })

    const match = await findMergeCandidateId(ctx.db, {
      accountId: accId,
      amount: -42.5,
      occurredAt: isoOffsetDays(0),
    })
    expect(match).toBeNull()
  })

  it('picks the closest candidate by (amountDiff, dateDiff)', async () => {
    const ctx = makeForecastDb()
    const accId = seedAccount(ctx)
    // Farther in date (3 days), exact amount.
    const far = seedTx(ctx, {
      accountId: accId,
      occurredAt: isoOffsetDays(3),
      amount: -42.5,
      status: 'scheduled',
    })
    // Same exact amount but closer in date (0 days) → should win.
    const near = seedTx(ctx, {
      accountId: accId,
      occurredAt: isoOffsetDays(0),
      amount: -42.5,
      status: 'scheduled',
    })

    const match = await findMergeCandidateId(ctx.db, {
      accountId: accId,
      amount: -42.5,
      occurredAt: isoOffsetDays(0),
    })
    expect(match).toBe(near)
    expect(match).not.toBe(far)
  })
})

describe('mergeBankTransactionMutation', () => {
  it('flips candidate to cleared with externalId, removes bank row, updates balance', async () => {
    const ctx = makeForecastDb()
    const mutations = createSqliteMutations(ctx.db)
    const accId = seedAccount(ctx, { id: 'c3333333-3333-4333-8333-3333333333aa', openingBalance: 1000 })

    // Scheduled DCA out-leg (-500), not yet realized.
    const candidateId = randomUUID()
    seedTx(ctx, {
      id: candidateId,
      accountId: accId,
      occurredAt: isoOffsetDays(1),
      amount: -500,
      status: 'scheduled',
      source: 'manual',
    })
    await recomputeAccountBalance(ctx.db, accId)
    expect(readBalance(ctx, accId)).toBe(1000) // scheduled excluded

    // Imported bank row matching it.
    const bankId = randomUUID()
    seedTx(ctx, {
      id: bankId,
      accountId: accId,
      occurredAt: isoOffsetDays(0),
      amount: -500,
      status: 'cleared',
      source: 'enable_banking',
      externalId: 'bank-ext-999',
      rawData: '{"k":"v"}',
      needsReview: true,
    })

    const res = await mutations.mergeBankTransaction(bankId, candidateId)
    expect(res.success).toBe(true)

    // Bank row gone.
    const bankRow = ctx.raw.prepare('SELECT id FROM transactions WHERE id = ?').get(bankId)
    expect(bankRow).toBeUndefined()

    // Candidate now cleared, carrying the bank's externalId / source / rawData.
    const merged = ctx.raw
      .prepare('SELECT status, external_id, source, raw_data, occurred_at FROM transactions WHERE id = ?')
      .get(candidateId) as {
      status: string
      external_id: string
      source: string
      raw_data: string
      occurred_at: string
    }
    expect(merged.status).toBe('cleared')
    expect(merged.external_id).toBe('bank-ext-999')
    expect(merged.source).toBe('enable_banking')
    expect(merged.raw_data).toBe('{"k":"v"}')
    expect(merged.occurred_at).toBe(isoOffsetDays(0)) // adopts bank date

    // Balance now includes the now-cleared -500 (occurred on/before today).
    await recomputeAccountBalance(ctx.db, accId)
    expect(readBalance(ctx, accId)).toBe(500)
  })

  it('rejects self-merge', async () => {
    const ctx = makeForecastDb()
    const mutations = createSqliteMutations(ctx.db)
    const id = randomUUID()
    const accId = seedAccount(ctx)
    seedTx(ctx, { id, accountId: accId, occurredAt: isoOffsetDays(0), amount: -10 })
    const res = await mutations.mergeBankTransaction(id, id)
    expect(res.success).toBe(false)
  })
})

describe('dismissMergeSuggestionMutation', () => {
  it('clears mergeSuggestedTxId on the bank row', async () => {
    const ctx = makeForecastDb()
    const mutations = createSqliteMutations(ctx.db)
    const accId = seedAccount(ctx)
    const bankId = randomUUID()
    const candidateId = randomUUID()
    seedTx(ctx, { id: bankId, accountId: accId, occurredAt: isoOffsetDays(0), amount: -10 })
    // Set a suggestion pointer directly.
    ctx.raw
      .prepare('UPDATE transactions SET merge_suggested_tx_id = ? WHERE id = ?')
      .run(candidateId, bankId)

    const res = await mutations.dismissMergeSuggestion(bankId)
    expect(res.success).toBe(true)

    const row = ctx.raw
      .prepare('SELECT merge_suggested_tx_id AS m FROM transactions WHERE id = ?')
      .get(bankId) as { m: string | null }
    expect(row.m).toBeNull()
  })
})
