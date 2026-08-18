import { describe, expect, it } from 'vitest'
import { getLeftToSpendThisMonth } from '@florin/db-sqlite/queries/dashboard'
import {
  makeForecastDb,
  seedAccount,
  seedTx,
  todayIso,
  type ForecastTestContext,
} from './forecast-test-helpers'

const GRP_INCOME = 'e1111111-1111-4111-8111-1111110000c1'
const GRP_EXPENSE = 'e1111111-1111-4111-8111-1111110000c2'
const CAT_SALARY = 'e2222222-2222-4222-8222-2222220000d1'
const CAT_MISC_INCOME = 'e2222222-2222-4222-8222-2222220000d2'
const CAT_GROCERIES = 'e2222222-2222-4222-8222-2222220000d3'

function seedGroups(ctx: ForecastTestContext): void {
  ctx.raw.exec(`
    INSERT INTO category_groups (id, name, kind, display_order) VALUES
      ('${GRP_INCOME}', 'Test Revenus', 'income', 0),
      ('${GRP_EXPENSE}', 'Test Dépenses', 'expense', 1);
    INSERT INTO categories (id, group_id, name, display_order) VALUES
      ('${CAT_SALARY}', '${GRP_INCOME}', 'Salaires', 0),
      ('${CAT_MISC_INCOME}', '${GRP_INCOME}', 'Gains additionnels', 1),
      ('${CAT_GROCERIES}', '${GRP_EXPENSE}', 'Courses', 0);
  `)
}

/** ISO date on the 15th of the Nth-previous calendar month (1 = last month). */
function isoMonthsAgo(n: number): string {
  const d = new Date()
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() - n, 15))
    .toISOString()
    .slice(0, 10)
}

describe('getLeftToSpendThisMonth — salary category detection', () => {
  it('a one-off inflow ≥ 500 does not hijack the salary category from the real salary', async () => {
    const ctx = makeForecastDb()
    seedGroups(ctx)
    const acc = seedAccount(ctx)

    // A real salary: same category, every month, ~3 000 €.
    seedTx(ctx, {
      accountId: acc,
      occurredAt: isoMonthsAgo(2),
      amount: 2994.76,
      payee: 'VIREMENT DE DIRECTION SPE FINANC',
      categoryId: CAT_SALARY,
    })
    seedTx(ctx, {
      accountId: acc,
      occurredAt: isoMonthsAgo(1),
      amount: 2998.98,
      payee: 'VIREMENT DE DIRECTION SPE FINANC',
      categoryId: CAT_SALARY,
    })
    // Small misc income this month, plus ONE 500 € cheque deposited today —
    // more recent than any salary, but a one-off.
    seedTx(ctx, {
      accountId: acc,
      occurredAt: todayIso(),
      amount: 87.21,
      payee: 'VIREMENT INSTANTANE CREDIT',
      categoryId: CAT_MISC_INCOME,
    })
    seedTx(ctx, {
      accountId: acc,
      occurredAt: todayIso(),
      amount: 500,
      payee: 'REMISE DE CHEQUE',
      categoryId: CAT_MISC_INCOME,
    })
    seedTx(ctx, {
      accountId: acc,
      occurredAt: todayIso(),
      amount: -400,
      payee: 'Vacances',
      categoryId: CAT_GROCERIES,
    })

    const lts = await getLeftToSpendThisMonth(ctx.db)

    // Recurrence wins over recency: 'Salaires' hit 2 distinct months,
    // 'Gains additionnels' only 1.
    expect(lts.salaryCategoryName).toBe('Salaires')
    // No salary yet this month → fall back to the last month that saw one,
    // NOT to the 587.21 of miscellaneous inflows.
    expect(lts.monthIncome).toBeCloseTo(2998.98, 2)
    expect(lts.leftToSpend).toBeCloseTo(2998.98 - 400, 2)
  })

  it('with a single month of history, the larger recurring inflow wins the tie', async () => {
    const ctx = makeForecastDb()
    seedGroups(ctx)
    const acc = seedAccount(ctx)
    seedTx(ctx, {
      accountId: acc,
      occurredAt: isoMonthsAgo(1),
      amount: 2200,
      payee: 'Employer',
      categoryId: CAT_SALARY,
    })
    seedTx(ctx, {
      accountId: acc,
      occurredAt: todayIso(),
      amount: 700,
      payee: 'Tax refund',
      categoryId: CAT_MISC_INCOME,
    })

    const lts = await getLeftToSpendThisMonth(ctx.db)
    expect(lts.salaryCategoryName).toBe('Salaires')
    expect(lts.monthIncome).toBeCloseTo(2200, 2)
  })

  it('uses the current month once the salary has actually landed', async () => {
    const ctx = makeForecastDb()
    seedGroups(ctx)
    const acc = seedAccount(ctx)
    seedTx(ctx, {
      accountId: acc,
      occurredAt: isoMonthsAgo(1),
      amount: 2994.76,
      payee: 'Employer',
      categoryId: CAT_SALARY,
    })
    seedTx(ctx, {
      accountId: acc,
      occurredAt: todayIso(),
      amount: 3100,
      payee: 'Employer',
      categoryId: CAT_SALARY,
    })

    const lts = await getLeftToSpendThisMonth(ctx.db)
    expect(lts.salaryCategoryName).toBe('Salaires')
    expect(lts.monthIncome).toBeCloseTo(3100, 2)
  })
})
