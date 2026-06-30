import { randomUUID } from 'node:crypto'
import { describe, expect, it } from 'vitest'
import {
  applyHoldingQuoteMutation,
  createSqliteMutations,
  createSqliteQueries,
  getNetWorth,
  listHoldingsToPrice,
  recomputeAccountBalance,
  recomputeMarketValue,
} from '@florin/db-sqlite'
import {
  ensureSchema,
  type SqliteDB,
} from '@florin/db-sqlite'
import {
  isoOffsetDays,
  makeForecastDb,
  readBalance,
  seedAccount,
  seedTx,
  todayIso,
  type ForecastTestContext,
} from './forecast-test-helpers'

// ---------- local helpers ----------

/** Read an account's cached market_value straight from the raw handle. */
function readMarketValue(ctx: ForecastTestContext, accountId: string): number {
  const row = ctx.raw
    .prepare('SELECT market_value AS m FROM accounts WHERE id = ?')
    .get(accountId) as { m: number } | undefined
  return row?.m ?? Number.NaN
}

interface SeedHoldingInput {
  id?: string
  accountId: string
  label?: string
  quantity: number
  costBasis: number
  quoteSymbol?: string | null
  isin?: string | null
  lastPrice?: number | null
  lastPriceAt?: string | null
}

/** Insert one holding directly (bypasses recompute). Returns its id. */
function seedHolding(ctx: ForecastTestContext, input: SeedHoldingInput): string {
  const id = input.id ?? randomUUID()
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
      input.label ?? 'World ETF',
      input.isin ?? null,
      input.quoteSymbol ?? null,
      input.quantity,
      input.costBasis,
      'EUR',
      input.lastPrice ?? null,
      input.lastPriceAt ?? null,
    )
  return id
}

/** Insert a transfer leg with optional status/deletedAt that seedTx can't set. */
function seedTransferLeg(
  ctx: ForecastTestContext,
  input: {
    accountId: string
    amount: number
    transferPairId: string
    status?: 'cleared' | 'scheduled'
    deletedAt?: string | null
    occurredAt?: string
  },
): string {
  const id = randomUUID()
  ctx.raw
    .prepare(
      `INSERT INTO transactions
         (id, account_id, occurred_at, amount, status, source, payee,
          transfer_pair_id, deleted_at, needs_review)
       VALUES (?, ?, ?, ?, ?, 'manual', '', ?, ?, 0)`,
    )
    .run(
      id,
      input.accountId,
      input.occurredAt ?? isoOffsetDays(-3),
      input.amount,
      input.status ?? 'cleared',
      input.transferPairId,
      input.deletedAt ?? null,
    )
  return id
}

/** A broker_portfolio account, included in net worth, manual provider. */
function seedBroker(ctx: ForecastTestContext, overrides: Record<string, unknown> = {}): string {
  return seedAccount(ctx, {
    name: 'PEA',
    kind: 'broker_portfolio',
    ...overrides,
  })
}

// =====================================================================
// 1. recomputeMarketValue / market_value
// =====================================================================

describe('recomputeMarketValue / market_value', () => {
  it('no holdings → market_value 0', async () => {
    const ctx = makeForecastDb()
    const broker = seedBroker(ctx)
    await recomputeMarketValue(ctx.db, broker)
    expect(readMarketValue(ctx, broker)).toBe(0)
  })

  it('holding with null price contributes 0', async () => {
    const ctx = makeForecastDb()
    const broker = seedBroker(ctx)
    seedHolding(ctx, { accountId: broker, quantity: 10, costBasis: 1000, lastPrice: null })
    await recomputeMarketValue(ctx.db, broker)
    expect(readMarketValue(ctx, broker)).toBe(0)
  })

  it('applyHoldingQuoteMutation sets price → recompute → market_value = qty × price', async () => {
    const ctx = makeForecastDb()
    const broker = seedBroker(ctx)
    const h = seedHolding(ctx, { accountId: broker, quantity: 10, costBasis: 1000 })

    const returnedAccountId = await applyHoldingQuoteMutation(ctx.db, h, 150, todayIso())
    expect(returnedAccountId).toBe(broker)

    await recomputeMarketValue(ctx.db, broker)
    expect(readMarketValue(ctx, broker)).toBe(1500) // 10 × 150
  })

  it('two holdings sum, and recompute is idempotent on re-run', async () => {
    const ctx = makeForecastDb()
    const broker = seedBroker(ctx)
    seedHolding(ctx, { accountId: broker, quantity: 10, costBasis: 1000, lastPrice: 150 })
    seedHolding(ctx, { accountId: broker, quantity: 4, costBasis: 800, lastPrice: 200 })

    await recomputeMarketValue(ctx.db, broker)
    expect(readMarketValue(ctx, broker)).toBe(2300) // 10×150 + 4×200

    // Re-running produces the same value (no drift).
    await recomputeMarketValue(ctx.db, broker)
    await recomputeMarketValue(ctx.db, broker)
    expect(readMarketValue(ctx, broker)).toBe(2300)
  })

  it('applyHoldingQuoteMutation on a missing holding returns null', async () => {
    const ctx = makeForecastDb()
    const result = await applyHoldingQuoteMutation(ctx.db, randomUUID(), 100, todayIso())
    expect(result).toBeNull()
  })
})

// =====================================================================
// 2. getNetWorth — broker marketValue + cash; loan branch; realized invariant
// =====================================================================

describe('getNetWorth — broker portfolio folding', () => {
  it('folds broker marketValue + currentBalance (cash) into gross', async () => {
    const ctx = makeForecastDb()
    const broker = seedBroker(ctx)
    seedHolding(ctx, { accountId: broker, quantity: 10, costBasis: 1000, lastPrice: 150 })
    await recomputeMarketValue(ctx.db, broker) // market_value = 1500

    // No cash yet.
    const nw1 = await getNetWorth(ctx.db)
    expect(nw1.gross).toBe(1500)
    expect(nw1.net).toBe(1500)

    // A cleared deposit raises cash (currentBalance) but NOT marketValue.
    seedTx(ctx, { accountId: broker, occurredAt: isoOffsetDays(-2), amount: 500, status: 'cleared' })
    await recomputeAccountBalance(ctx.db, broker)
    expect(readBalance(ctx, broker)).toBe(500)
    expect(readMarketValue(ctx, broker)).toBe(1500) // unchanged

    const nw2 = await getNetWorth(ctx.db)
    expect(nw2.gross).toBe(2000) // 1500 holdings + 500 cash
    expect(nw2.net).toBe(2000)
  })

  it('sums broker + checking + loan branches independently', async () => {
    const ctx = makeForecastDb()
    const checking = seedAccount(ctx, { name: 'CCP', kind: 'checking', openingBalance: 3000 })
    await recomputeAccountBalance(ctx.db, checking) // 3000 cash

    const broker = seedBroker(ctx)
    seedHolding(ctx, { accountId: broker, quantity: 5, costBasis: 1000, lastPrice: 300 })
    await recomputeMarketValue(ctx.db, broker) // 1500

    // A loan account: its branch contributes to liability, not gross.
    const loan = seedAccount(ctx, {
      name: 'Mortgage',
      kind: 'loan',
      openingBalance: 0,
    })
    // Give the loan a remaining-debt via a negative balance row.
    seedTx(ctx, { accountId: loan, occurredAt: isoOffsetDays(-5), amount: -10000, status: 'cleared' })
    await recomputeAccountBalance(ctx.db, loan)

    const nw = await getNetWorth(ctx.db)
    // gross = checking 3000 + broker (1500 holdings + 0 cash) = 4500
    expect(nw.gross).toBe(4500)
    // liability comes from the loan branch (>= 0); net = gross − liability.
    expect(nw.net).toBe(nw.gross - nw.liability)
    expect(nw.liability).toBeGreaterThanOrEqual(0)
  })

  it('realized-balance invariant: a scheduled/future tx on the broker does not move cash', async () => {
    const ctx = makeForecastDb()
    const broker = seedBroker(ctx)
    seedTx(ctx, { accountId: broker, occurredAt: isoOffsetDays(-2), amount: 500, status: 'cleared' })
    await recomputeAccountBalance(ctx.db, broker)
    expect(readBalance(ctx, broker)).toBe(500)

    // Add a scheduled (future) deposit — must not change currentBalance.
    seedTx(ctx, { accountId: broker, occurredAt: isoOffsetDays(20), amount: 9999, status: 'scheduled' })
    await recomputeAccountBalance(ctx.db, broker)
    expect(readBalance(ctx, broker)).toBe(500) // unchanged

    const nw = await getNetWorth(ctx.db)
    expect(nw.net).toBe(500) // only realized cash, no holdings here
  })
})

// =====================================================================
// 3. getPortfolioValuation — marketValue, costBasis, plusValue, cash, verse, marche
// =====================================================================

describe('getPortfolioValuation', () => {
  it('computes the full aggregate with only inbound cleared transfer legs as verse', async () => {
    const ctx = makeForecastDb()
    const broker = seedBroker(ctx)
    const q = createSqliteQueries(ctx.db)

    // Holdings with a market price.
    seedHolding(ctx, { accountId: broker, quantity: 10, costBasis: 1000, lastPrice: 150 }) // mv 1500
    seedHolding(ctx, { accountId: broker, quantity: 5, costBasis: 800, lastPrice: 100 }) //  mv 500
    await recomputeMarketValue(ctx.db, broker) // market_value = 2000, costBasis Σ = 1800

    // Idle cash: a cleared positive deposit (no transfer pair) raises currentBalance.
    seedTx(ctx, { accountId: broker, occurredAt: isoOffsetDays(-4), amount: 300, status: 'cleared' })

    // Inbound cleared transfer legs (count toward verse): +1000 and +500.
    seedTransferLeg(ctx, { accountId: broker, amount: 1000, transferPairId: randomUUID(), status: 'cleared' })
    seedTransferLeg(ctx, { accountId: broker, amount: 500, transferPairId: randomUUID(), status: 'cleared' })

    // Outbound cleared transfer leg (negative) — must NOT count toward verse.
    seedTransferLeg(ctx, { accountId: broker, amount: -200, transferPairId: randomUUID(), status: 'cleared' })

    // Uncleared/scheduled inbound transfer leg — must NOT count toward verse.
    seedTransferLeg(ctx, { accountId: broker, amount: 400, transferPairId: randomUUID(), status: 'scheduled' })

    // Deleted inbound transfer leg — must NOT count toward verse.
    seedTransferLeg(ctx, {
      accountId: broker,
      amount: 700,
      transferPairId: randomUUID(),
      status: 'cleared',
      deletedAt: new Date().toISOString(),
    })

    await recomputeAccountBalance(ctx.db, broker)

    const v = await q.getPortfolioValuation(broker)

    // cash = currentBalance = realized cleared rows on/before today.
    // = 300 (deposit) + 1000 + 500 (inbound) − 200 (outbound) = 1600.
    // (scheduled +400 and deleted +700 excluded by recomputeAccountBalance.)
    expect(v.cash).toBe(1600)
    expect(v.marketValue).toBe(2000)
    expect(v.costBasis).toBe(1800)
    expect(v.plusValue).toBe(200) // 2000 − 1800
    // verse counts ONLY inbound (amount>0), cleared, non-deleted transfer legs = 1000 + 500.
    expect(v.verse).toBe(1500)
    // marche = (marketValue + cash) − verse = (2000 + 1600) − 1500 = 2100.
    expect(v.marche).toBe(2100)
  })

  it('empty broker → all zeros', async () => {
    const ctx = makeForecastDb()
    const broker = seedBroker(ctx)
    const q = createSqliteQueries(ctx.db)
    const v = await q.getPortfolioValuation(broker)
    expect(v).toEqual({ marketValue: 0, costBasis: 0, plusValue: 0, cash: 0, verse: 0, marche: 0 })
  })

  it('plusValuePct is null when costBasis is 0 (via listHoldings HoldingView)', async () => {
    const ctx = makeForecastDb()
    const broker = seedBroker(ctx)
    const q = createSqliteQueries(ctx.db)
    // costBasis 0 but a price set → marketValue > 0, plusValue > 0, pct null.
    seedHolding(ctx, { accountId: broker, quantity: 3, costBasis: 0, lastPrice: 50 })

    const views = await q.listHoldings(broker)
    expect(views).toHaveLength(1)
    const hv = views[0]
    expect(hv.marketValue).toBe(150)
    expect(hv.plusValue).toBe(150)
    expect(hv.plusValuePct).toBeNull()

    // Sanity: a holding WITH costBasis returns a numeric pct.
    seedHolding(ctx, { accountId: broker, quantity: 2, costBasis: 100, lastPrice: 75 })
    const views2 = await q.listHoldings(broker)
    const withCost = views2.find((v) => v.costBasis === 100)!
    expect(withCost.plusValuePct).toBeCloseTo(50, 5) // (150−100)/100 × 100
  })
})

// =====================================================================
// 4. Mutations recompute market value
// =====================================================================

describe('addHolding / updateHolding / deleteHolding recompute market value', () => {
  it('addHolding recomputes; updateHolding(quantity) changes it; deleteHolding drops it', async () => {
    const ctx = makeForecastDb()
    const broker = seedBroker(ctx)
    const m = createSqliteMutations(ctx.db)

    // addHolding with no price → market_value stays 0.
    const add1 = await m.addHolding({
      accountId: broker,
      label: 'World ETF',
      quantity: 10,
      costBasis: 1000,
    })
    expect(add1.success).toBe(true)
    expect(readMarketValue(ctx, broker)).toBe(0)

    const holdingId = (add1 as { success: true; data: { id: string } }).data.id

    // Give it a price, then update quantity → recompute via updateHolding.
    await applyHoldingQuoteMutation(ctx.db, holdingId, 100, todayIso())
    const upd = await m.updateHolding(holdingId, { quantity: 20 })
    expect(upd.success).toBe(true)
    expect(readMarketValue(ctx, broker)).toBe(2000) // 20 × 100

    // updateHolding changing quantity again moves market value.
    const upd2 = await m.updateHolding(holdingId, { quantity: 5 })
    expect(upd2.success).toBe(true)
    expect(readMarketValue(ctx, broker)).toBe(500) // 5 × 100

    // deleteHolding drops market value to 0.
    const del = await m.deleteHolding(holdingId)
    expect(del.success).toBe(true)
    expect(readMarketValue(ctx, broker)).toBe(0)
  })

  it('deleteHolding leaves other holdings intact in the recomputed value', async () => {
    const ctx = makeForecastDb()
    const broker = seedBroker(ctx)
    const m = createSqliteMutations(ctx.db)

    const a = await m.addHolding({ accountId: broker, label: 'A', quantity: 1, costBasis: 100 })
    const b = await m.addHolding({ accountId: broker, label: 'B', quantity: 2, costBasis: 200 })
    const aId = (a as { data: { id: string } }).data.id
    const bId = (b as { data: { id: string } }).data.id

    await applyHoldingQuoteMutation(ctx.db, aId, 100, todayIso())
    await applyHoldingQuoteMutation(ctx.db, bId, 50, todayIso())
    await recomputeMarketValue(ctx.db, broker)
    expect(readMarketValue(ctx, broker)).toBe(200) // 1×100 + 2×50

    await m.deleteHolding(aId)
    expect(readMarketValue(ctx, broker)).toBe(100) // only B remains: 2×50
  })
})

// =====================================================================
// 4b. buyHolding — one-click buy: add shares + deduct cash in one step
// =====================================================================

describe('buyHolding — cash → shares in one action', () => {
  it('buying a NEW holding creates it (quantity/costBasis), drops cash, and market value follows a price', async () => {
    const ctx = makeForecastDb()
    // Broker with €1000 idle cash to buy from.
    const broker = seedBroker(ctx, { openingBalance: 1000, currentBalance: 1000 })
    const m = createSqliteMutations(ctx.db)
    const q = createSqliteQueries(ctx.db)

    const result = await m.buyHolding({
      accountId: broker,
      label: 'World ETF',
      quoteSymbol: 'WPEA.PA',
      quantity: 4,
      amount: 500,
    })
    expect(result.success).toBe(true)
    const holdingId = (result as { success: true; data: { holdingId: string } }).data.holdingId
    expect(holdingId).not.toBe('')

    // The new holding carries quantity 4 and costBasis = amount spent (500).
    const views = await q.listHoldings(broker)
    expect(views).toHaveLength(1)
    expect(views[0].id).toBe(holdingId)
    expect(views[0].quantity).toBe(4)
    expect(views[0].costBasis).toBe(500)

    // Cash dropped by the amount: 1000 − 500 = 500.
    expect(readBalance(ctx, broker)).toBe(500)

    // No price yet → market value 0; once priced it reflects qty × price.
    expect(readMarketValue(ctx, broker)).toBe(0)
    await applyHoldingQuoteMutation(ctx.db, holdingId, 130, todayIso())
    await recomputeMarketValue(ctx.db, broker)
    expect(readMarketValue(ctx, broker)).toBe(520) // 4 × 130
  })

  it('buying into an EXISTING holding increments quantity + costBasis and deducts cash again', async () => {
    const ctx = makeForecastDb()
    const broker = seedBroker(ctx, { openingBalance: 2000, currentBalance: 2000 })
    const m = createSqliteMutations(ctx.db)
    const q = createSqliteQueries(ctx.db)

    // First buy: creates the holding (qty 4, costBasis 500), cash 2000 → 1500.
    const first = await m.buyHolding({
      accountId: broker,
      label: 'World ETF',
      quoteSymbol: 'WPEA.PA',
      quantity: 4,
      amount: 500,
    })
    expect(first.success).toBe(true)
    const holdingId = (first as { success: true; data: { holdingId: string } }).data.holdingId
    expect(readBalance(ctx, broker)).toBe(1500)

    // Second buy into the SAME holding via holdingId: qty 4→6, costBasis 500→800.
    const second = await m.buyHolding({
      accountId: broker,
      holdingId,
      quantity: 2,
      amount: 300,
    })
    expect(second.success).toBe(true)
    expect((second as { success: true; data: { holdingId: string } }).data.holdingId).toBe(holdingId)

    const views = await q.listHoldings(broker)
    expect(views).toHaveLength(1) // still one holding, not a duplicate
    expect(views[0].quantity).toBe(6) // 4 + 2
    expect(views[0].costBasis).toBe(800) // 500 + 300

    // Cash deducted again: 1500 − 300 = 1200.
    expect(readBalance(ctx, broker)).toBe(1200)
  })
})

// =====================================================================
// 5. listHoldingsToPrice — only holdings with a quoteSymbol
// =====================================================================

describe('listHoldingsToPrice', () => {
  it('returns only holdings with a non-null quoteSymbol', async () => {
    const ctx = makeForecastDb()
    const broker = seedBroker(ctx)
    const withSym = seedHolding(ctx, {
      accountId: broker,
      label: 'CW8',
      quoteSymbol: 'CW8.PA',
      quantity: 10,
      costBasis: 1000,
    })
    // No quoteSymbol → excluded.
    seedHolding(ctx, { accountId: broker, label: 'Cash position', quoteSymbol: null, quantity: 5, costBasis: 500 })

    const list = await listHoldingsToPrice(ctx.db)
    expect(list).toHaveLength(1)
    expect(list[0].id).toBe(withSym)
    expect(list[0].quoteSymbol).toBe('CW8.PA')
    expect(list[0].accountId).toBe(broker)
  })

  it('returns an empty list when no holding has a quoteSymbol', async () => {
    const ctx = makeForecastDb()
    const broker = seedBroker(ctx)
    seedHolding(ctx, { accountId: broker, quoteSymbol: null, quantity: 1, costBasis: 10 })
    const list = await listHoldingsToPrice(ctx.db)
    expect(list).toEqual([])
  })
})

// =====================================================================
// 6. Migration idempotency
// =====================================================================

describe('ensureSchema idempotency', () => {
  it('calling ensureSchema twice does not error and leaves balances unchanged', async () => {
    const ctx = makeForecastDb() // ensureSchema already ran once inside the helper
    const acc = seedAccount(ctx, { name: 'Savings', openingBalance: 1234, currentBalance: 1234 })
    seedTx(ctx, { accountId: acc, occurredAt: isoOffsetDays(-1), amount: 66, status: 'cleared' })
    await recomputeAccountBalance(ctx.db, acc)
    const before = readBalance(ctx, acc)
    expect(before).toBe(1300) // 1234 opening + 66

    // Second pass must be a no-op.
    expect(() => ensureSchema(ctx.db as SqliteDB)).not.toThrow()

    // Tables + columns still present.
    const tables = ctx.raw
      .prepare("SELECT name FROM sqlite_master WHERE type='table' AND name='holdings'")
      .all() as Array<{ name: string }>
    expect(tables).toHaveLength(1)

    const cols = ctx.raw.prepare('PRAGMA table_info(accounts)').all() as Array<{ name: string }>
    expect(cols.some((c) => c.name === 'market_value')).toBe(true)

    // Balance unchanged.
    expect(readBalance(ctx, acc)).toBe(before)
  })
})
