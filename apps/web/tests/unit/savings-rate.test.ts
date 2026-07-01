import { describe, expect, it } from 'vitest'
import { getSavingsRates } from '@florin/db-sqlite/queries/dashboard'
import { makeForecastDb, seedAccount, seedTx, todayIso, type ForecastTestContext } from './forecast-test-helpers'

const GRP_INCOME = 'd1111111-1111-4111-8111-1111110000a1'
const GRP_EXPENSE = 'd1111111-1111-4111-8111-1111110000a2'
const CAT_SALARY = 'd2222222-2222-4222-8222-2222220000b1'
const CAT_DINING = 'd2222222-2222-4222-8222-2222220000b2'

function seedGroups(ctx: ForecastTestContext): void {
  ctx.raw.exec(`
    INSERT INTO category_groups (id, name, kind, display_order) VALUES
      ('${GRP_INCOME}', 'Income', 'income', 0),
      ('${GRP_EXPENSE}', 'Dining', 'expense', 1);
    INSERT INTO categories (id, group_id, name, display_order) VALUES
      ('${CAT_SALARY}', '${GRP_INCOME}', 'Salary', 0),
      ('${CAT_DINING}', '${GRP_EXPENSE}', 'Restaurants', 1);
  `)
}

describe('getSavingsRates — reimbursements net against their expense category', () => {
  it('a refund booked into an expense category offsets that expense (not ignored)', async () => {
    const ctx = makeForecastDb()
    seedGroups(ctx)
    const acc = seedAccount(ctx, { openingBalance: 0 })
    const today = todayIso()
    // 1000 salary, 300 shared dinner, 225 repaid by friends into the SAME
    // dining category. True savings = 1000 − (300 − 225) = 925 → 92.5%.
    seedTx(ctx, { accountId: acc, occurredAt: today, amount: 1000, payee: 'Employer', categoryId: CAT_SALARY })
    seedTx(ctx, { accountId: acc, occurredAt: today, amount: -300, payee: 'Group dinner', categoryId: CAT_DINING })
    seedTx(ctx, { accountId: acc, occurredAt: today, amount: 225, payee: 'Friends refund', categoryId: CAT_DINING })

    const rates = await getSavingsRates(ctx.db)
    // Netted: (1000 − 75) / 1000 = 92.5%. The old formula ignored the +225 and
    // would have returned 70%.
    expect(rates.threeMonth).toBeCloseTo(92.5, 1)
    expect(rates.twelveMonth).toBeCloseTo(92.5, 1)
  })

  it('ignores uncategorized rows (synthetic balance adjustments, unlinked transfers)', async () => {
    const ctx = makeForecastDb()
    seedGroups(ctx)
    const acc = seedAccount(ctx, { openingBalance: 0 })
    const today = todayIso()
    // 1000 salary, 200 real categorized expense → 80%. A +500 UNcategorized
    // "Balance Adjustment" must NOT lift the rate (it's not real income/spend).
    seedTx(ctx, { accountId: acc, occurredAt: today, amount: 1000, payee: 'Employer', categoryId: CAT_SALARY })
    seedTx(ctx, { accountId: acc, occurredAt: today, amount: -200, payee: 'Rent', categoryId: CAT_DINING })
    seedTx(ctx, { accountId: acc, occurredAt: today, amount: 500, payee: 'Reconciliation Balance Adjustment', categoryId: null })

    const rates = await getSavingsRates(ctx.db)
    expect(rates.threeMonth).toBeCloseTo(80, 1)
  })

  it('null (not 0%) when there is no income in the window', async () => {
    const ctx = makeForecastDb()
    seedGroups(ctx)
    const acc = seedAccount(ctx)
    seedTx(ctx, { accountId: acc, occurredAt: todayIso(), amount: -50, payee: 'Coffee', categoryId: CAT_DINING })
    const rates = await getSavingsRates(ctx.db)
    expect(rates.threeMonth).toBeNull()
  })
})
