import { describe, expect, it } from 'vitest'
import { getMonthPlanQuery } from '@florin/db-sqlite/queries/plan'
import { makeTestDb, seedPlanFixture } from './plan-test-helpers'

describe('getMonthPlanQuery', () => {
  it('returns an empty-ish plan when no budgets exist and no transactions', () => {
    const ctx = makeTestDb()
    seedPlanFixture(ctx)

    // Query a month with no transactions or budgets (May 2026).
    const plan = getMonthPlanQuery(ctx.db, 2026, 5)

    expect(plan.year).toBe(2026)
    expect(plan.month).toBe(5)
    expect(plan.income).toBe(0)
    expect(plan.totalAssigned).toBe(0)
    expect(plan.readyToAssign).toBe(0)
    expect(plan.overspentCount).toBe(0)
    // Bills group present, Salary (income) excluded from groups[].
    expect(plan.groups).toHaveLength(1)
    expect(plan.groups[0].name).toBe('Bills')
    expect(plan.groups[0].kind).toBe('expense')
    expect(plan.groups[0].categories).toHaveLength(2)
    for (const c of plan.groups[0].categories) {
      expect(c.assigned).toBe(0)
      expect(c.spent).toBe(0)
      expect(c.available).toBe(0)
    }
  })

  it('computes spent per category, income, and ready-to-assign for April 2026', () => {
    const ctx = makeTestDb()
    const ids = seedPlanFixture(ctx)
    // Assign 1000€ to Rent, 200€ to Groceries.
    ctx.raw.exec(`
      INSERT INTO monthly_budgets (id, year, month, category_id, assigned) VALUES
        ('mb-rent', 2026, 4, '${ids.catRentId}', 1000.00),
        ('mb-groc', 2026, 4, '${ids.catGroceriesId}', 200.00);
    `)

    const plan = getMonthPlanQuery(ctx.db, 2026, 4)

    expect(plan.income).toBe(3000)
    expect(plan.totalAssigned).toBe(1200)
    expect(plan.readyToAssign).toBe(1800)

    const bills = plan.groups[0]
    expect(bills.assigned).toBe(1200)
    expect(bills.spent).toBe(995) // 915 + 50 + 30
    expect(bills.available).toBe(205)
    expect(bills.overspentCount).toBe(0)

    const rent = bills.categories.find((c) => c.id === ids.catRentId)!
    expect(rent.assigned).toBe(1000)
    expect(rent.spent).toBe(915)
    expect(rent.available).toBe(85)

    const groc = bills.categories.find((c) => c.id === ids.catGroceriesId)!
    expect(groc.assigned).toBe(200)
    expect(groc.spent).toBe(80)
    expect(groc.available).toBe(120)
  })

  it('flags overspent categories when available < 0', () => {
    const ctx = makeTestDb()
    const ids = seedPlanFixture(ctx)
    ctx.raw.exec(`
      INSERT INTO monthly_budgets (id, year, month, category_id, assigned) VALUES
        ('mb-rent', 2026, 4, '${ids.catRentId}', 500.00);
    `) // Rent spent 915 but only 500 assigned → overspent.

    const plan = getMonthPlanQuery(ctx.db, 2026, 4)
    const rent = plan.groups[0].categories.find((c) => c.id === ids.catRentId)!
    expect(rent.available).toBe(-415)
    expect(plan.groups[0].overspentCount).toBe(1)
    expect(plan.overspentCount).toBe(1)
  })

  it('excludes transfers from income and spent', () => {
    const ctx = makeTestDb()
    const ids = seedPlanFixture(ctx)
    ctx.raw.exec(`
      INSERT INTO transactions (id, account_id, occurred_at, amount, category_id, source, payee, transfer_pair_id) VALUES
        ('tx-xfer-out', '${ids.accountId}', '2026-04-12', -500.00, '${ids.catRentId}', 'manual', 'Transfer', 'pair-1'),
        ('tx-xfer-in', '${ids.accountId}', '2026-04-12', 500.00, '${ids.catSalaryId}', 'manual', 'Transfer', 'pair-1');
    `)

    const plan = getMonthPlanQuery(ctx.db, 2026, 4)
    expect(plan.income).toBe(3000) // unchanged, transfer excluded
    const rent = plan.groups[0].categories.find((c) => c.id === ids.catRentId)!
    expect(rent.spent).toBe(915) // unchanged, transfer excluded
  })

  it('excludes soft-deleted transactions', () => {
    const ctx = makeTestDb()
    const ids = seedPlanFixture(ctx)
    ctx.raw.exec(`
      UPDATE transactions SET deleted_at = '2026-04-15' WHERE id = 'tx-groc-apr-1';
    `)

    const plan = getMonthPlanQuery(ctx.db, 2026, 4)
    const groc = plan.groups[0].categories.find((c) => c.id === ids.catGroceriesId)!
    expect(groc.spent).toBe(30) // only the un-deleted Monoprix tx
  })

  it('includes pending transactions in spent', () => {
    const ctx = makeTestDb()
    const ids = seedPlanFixture(ctx)
    ctx.raw.exec(`
      UPDATE transactions SET is_pending = 1 WHERE id = 'tx-groc-apr-1';
    `)

    const plan = getMonthPlanQuery(ctx.db, 2026, 4)
    const groc = plan.groups[0].categories.find((c) => c.id === ids.catGroceriesId)!
    expect(groc.spent).toBe(80) // both included, pending or not
  })

  it('hides archived categories from the grid', () => {
    const ctx = makeTestDb()
    const ids = seedPlanFixture(ctx)
    ctx.raw.exec(`
      UPDATE categories SET is_archived = 1 WHERE id = '${ids.catGroceriesId}';
    `)

    const plan = getMonthPlanQuery(ctx.db, 2026, 4)
    const catIds = plan.groups[0].categories.map((c) => c.id)
    expect(catIds).not.toContain(ids.catGroceriesId)
    expect(catIds).toContain(ids.catRentId)
  })

  it('respects group display_order', () => {
    const ctx = makeTestDb()
    seedPlanFixture(ctx)
    ctx.raw.exec(`
      INSERT INTO category_groups (id, name, kind, display_order) VALUES
        ('grp-wants', 'Wants', 'expense', 0);
    `) // Lower display_order than Bills — should come first.

    const plan = getMonthPlanQuery(ctx.db, 2026, 4)
    expect(plan.groups.map((g) => g.name)).toEqual(['Wants', 'Bills'])
  })
})
