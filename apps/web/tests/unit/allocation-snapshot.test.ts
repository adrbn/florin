import { randomUUID } from 'node:crypto'
import { describe, expect, it } from 'vitest'
import { createSqliteQueries, recomputeAccountBalance, recomputeMarketValue } from '@florin/db-sqlite'
import {
  isoOffsetDays,
  makeForecastDb,
  seedAccount,
  seedTx,
  type ForecastTestContext,
} from './forecast-test-helpers'

/** Insert one holding directly (bypasses recompute). Returns its id. */
function seedHolding(
  ctx: ForecastTestContext,
  input: {
    accountId: string
    quantity: number
    costBasis: number
    lastPrice?: number | null
  },
): string {
  const id = randomUUID()
  ctx.raw
    .prepare(
      `INSERT INTO holdings
         (id, account_id, label, isin, quote_symbol, quantity, cost_basis,
          currency, last_price, last_price_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    )
    .run(
      id,
      input.accountId,
      'World ETF',
      null,
      null,
      input.quantity,
      input.costBasis,
      'EUR',
      input.lastPrice ?? null,
      null,
    )
  return id
}

/** Insert an active monthly recurring transfer rule into `toAccountId`. */
function seedMonthlyTransferRule(
  ctx: ForecastTestContext,
  input: { fromAccountId: string; toAccountId: string; amount: number; interval?: number },
): string {
  const id = randomUUID()
  ctx.raw
    .prepare(
      `INSERT INTO recurring_rules
         (id, name, kind, account_id, to_account_id, amount, payee, currency,
          frequency, interval, day_of_month, start_date, is_active)
       VALUES (?, ?, 'transfer', ?, ?, ?, '', 'EUR', 'monthly', ?, 1, ?, 1)`,
    )
    .run(
      id,
      'DCA',
      input.fromAccountId,
      input.toAccountId,
      input.amount,
      input.interval ?? 1,
      isoOffsetDays(-30),
    )
  return id
}

describe('getNetWorthAllocation', () => {
  it('partitions net worth into cash / invested / loans buckets', async () => {
    const ctx = makeForecastDb()
    const q = createSqliteQueries(ctx.db)

    // Checking account → cash bucket (3000).
    const checking = seedAccount(ctx, { name: 'CCP', kind: 'checking' })
    seedTx(ctx, { accountId: checking, occurredAt: isoOffsetDays(-5), amount: 3000, status: 'cleared' })
    await recomputeAccountBalance(ctx.db, checking)

    // Broker portfolio → invested (marketValue + idle cash inside the wrapper).
    const broker = seedAccount(ctx, { name: 'PEA', kind: 'broker_portfolio' })
    seedHolding(ctx, { accountId: broker, quantity: 10, costBasis: 1000, lastPrice: 200 }) // mv 2000
    await recomputeMarketValue(ctx.db, broker)
    seedTx(ctx, { accountId: broker, occurredAt: isoOffsetDays(-4), amount: 500, status: 'cleared' }) // idle cash 500
    await recomputeAccountBalance(ctx.db, broker)

    // Loan account with a negative balance → loans bucket (> 0).
    const loan = seedAccount(ctx, { name: 'Mortgage', kind: 'loan' })
    seedTx(ctx, { accountId: loan, occurredAt: isoOffsetDays(-6), amount: -10000, status: 'cleared' })
    await recomputeAccountBalance(ctx.db, loan)

    const alloc = await q.getNetWorthAllocation()

    // cash = checking only — money inside the investment wrapper is not
    // day-to-day cash.
    expect(alloc.cash).toBe(3000)
    // invested = broker marketValue (holdings) + idle cash sitting in the
    // wrapper (versements not yet deployed).
    expect(alloc.invested).toBe(2500)
    // loans = remaining debt of the loan account (positive magnitude).
    expect(alloc.loans).toBeGreaterThan(0)
  })

  it('all-zero when there are no included accounts', async () => {
    const ctx = makeForecastDb()
    const q = createSqliteQueries(ctx.db)
    const alloc = await q.getNetWorthAllocation()
    expect(alloc).toEqual({ cash: 0, invested: 0, loans: 0 })
  })
})

describe('getInvestmentSnapshot', () => {
  it('sums broker value and active monthly transfers into the broker (DCA)', async () => {
    const ctx = makeForecastDb()
    const q = createSqliteQueries(ctx.db)

    const checking = seedAccount(ctx, { name: 'CCP', kind: 'checking' })

    const broker = seedAccount(ctx, { name: 'PEA', kind: 'broker_portfolio' })
    seedHolding(ctx, { accountId: broker, quantity: 10, costBasis: 1000, lastPrice: 200 }) // mv 2000
    await recomputeMarketValue(ctx.db, broker)
    seedTx(ctx, { accountId: broker, occurredAt: isoOffsetDays(-4), amount: 300, status: 'cleared' }) // idle cash 300
    await recomputeAccountBalance(ctx.db, broker)

    // A monthly €500 transfer into the broker — the DCA.
    seedMonthlyTransferRule(ctx, { fromAccountId: checking, toAccountId: broker, amount: 500 })
    // A transfer into checking (NOT a broker) must not count.
    seedMonthlyTransferRule(ctx, { fromAccountId: broker, toAccountId: checking, amount: 999 })

    const snap = await q.getInvestmentSnapshot()

    // investedValue = broker marketValue 2000 + idle cash 300.
    expect(snap.investedValue).toBe(2300)
    // monthlyContribution = €500 DCA into the broker.
    expect(snap.monthlyContribution).toBe(500)
  })

  it('zero contribution when no active broker transfer rule exists', async () => {
    const ctx = makeForecastDb()
    const q = createSqliteQueries(ctx.db)
    const broker = seedAccount(ctx, { name: 'PEA', kind: 'broker_portfolio' })
    seedHolding(ctx, { accountId: broker, quantity: 1, costBasis: 100, lastPrice: 150 })
    await recomputeMarketValue(ctx.db, broker)

    const snap = await q.getInvestmentSnapshot()
    expect(snap.investedValue).toBe(150)
    expect(snap.monthlyContribution).toBe(0)
  })
})
