import { describe, expect, it } from 'vitest'
import { createSqliteMutations } from '@florin/db-sqlite/actions'
import { getMonthPlanQuery } from '@florin/db-sqlite/queries/plan'
import { makeTestDb, seedMutationFixture } from './plan-test-helpers'

describe('setCategoryAssigned', () => {
  it('inserts a new row when none exists, storing assigned + note', async () => {
    const ctx = makeTestDb()
    const ids = seedMutationFixture(ctx)
    const mutations = createSqliteMutations(ctx.db)

    const result = await mutations.setCategoryAssigned({
      year: 2026,
      month: 4,
      categoryId: ids.catRentId,
      amount: 1200,
      note: 'monthly rent',
    })

    expect(result.success).toBe(true)

    const row = ctx.raw
      .prepare('SELECT assigned, note FROM monthly_budgets WHERE category_id = ? AND year = ? AND month = ?')
      .get(ids.catRentId, 2026, 4) as { assigned: number; note: string | null } | undefined

    expect(row).toBeDefined()
    expect(row!.assigned).toBe(1200)
    expect(row!.note).toBe('monthly rent')
  })

  it('updates an existing row — second call wins, only 1 row in table', async () => {
    const ctx = makeTestDb()
    const ids = seedMutationFixture(ctx)
    const mutations = createSqliteMutations(ctx.db)

    await mutations.setCategoryAssigned({
      year: 2026,
      month: 4,
      categoryId: ids.catRentId,
      amount: 1000,
    })
    const result = await mutations.setCategoryAssigned({
      year: 2026,
      month: 4,
      categoryId: ids.catRentId,
      amount: 1500,
    })

    expect(result.success).toBe(true)

    const rows = ctx.raw
      .prepare('SELECT assigned FROM monthly_budgets WHERE category_id = ? AND year = ? AND month = ?')
      .all(ids.catRentId, 2026, 4) as { assigned: number }[]

    expect(rows).toHaveLength(1)
    expect(rows[0].assigned).toBe(1500)
  })

  it('rejects negative amount (returns success: false)', async () => {
    const ctx = makeTestDb()
    const ids = seedMutationFixture(ctx)
    const mutations = createSqliteMutations(ctx.db)

    const result = await mutations.setCategoryAssigned({
      year: 2026,
      month: 4,
      categoryId: ids.catRentId,
      amount: -50,
    })

    expect(result.success).toBe(false)
    expect(result.error).toBeDefined()
  })

  it('rejects an unknown categoryId (returns success: false)', async () => {
    const ctx = makeTestDb()
    seedMutationFixture(ctx)
    const mutations = createSqliteMutations(ctx.db)

    const result = await mutations.setCategoryAssigned({
      year: 2026,
      month: 4,
      categoryId: '00000000-0000-0000-0000-000000000000',
      amount: 100,
    })

    expect(result.success).toBe(false)
    expect(result.error).toMatch(/not found/i)
  })

  it('rejects month outside 1..12 (returns success: false)', async () => {
    const ctx = makeTestDb()
    const ids = seedMutationFixture(ctx)
    const mutations = createSqliteMutations(ctx.db)

    const tooLow = await mutations.setCategoryAssigned({
      year: 2026,
      month: 0,
      categoryId: ids.catRentId,
      amount: 100,
    })
    expect(tooLow.success).toBe(false)

    const tooHigh = await mutations.setCategoryAssigned({
      year: 2026,
      month: 13,
      categoryId: ids.catRentId,
      amount: 100,
    })
    expect(tooHigh.success).toBe(false)
  })

  it('preserves existing note when note is omitted on update; clears note when note is explicitly null', async () => {
    // Semantics: undefined note = PATCH (preserve existing); null note = clear explicitly.
    const ctx = makeTestDb()
    const ids = seedMutationFixture(ctx)
    const mutations = createSqliteMutations(ctx.db)

    // First call: set with a note.
    await mutations.setCategoryAssigned({
      year: 2026,
      month: 4,
      categoryId: ids.catRentId,
      amount: 1000,
      note: 'original note',
    })

    // Second call: omit note (undefined) → note should be preserved.
    await mutations.setCategoryAssigned({
      year: 2026,
      month: 4,
      categoryId: ids.catRentId,
      amount: 1100,
      // note intentionally not passed
    })

    const afterOmit = ctx.raw
      .prepare('SELECT note FROM monthly_budgets WHERE category_id = ? AND year = ? AND month = ?')
      .get(ids.catRentId, 2026, 4) as { note: string | null }

    expect(afterOmit.note).toBe('original note')

    // Third call: pass note: null explicitly → note should be cleared.
    await mutations.setCategoryAssigned({
      year: 2026,
      month: 4,
      categoryId: ids.catRentId,
      amount: 1100,
      note: null,
    })

    const afterNull = ctx.raw
      .prepare('SELECT note FROM monthly_budgets WHERE category_id = ? AND year = ? AND month = ?')
      .get(ids.catRentId, 2026, 4) as { note: string | null }

    expect(afterNull.note).toBeNull()
  })
})

describe('clearCategoryAssigned', () => {
  it('removes the budget row; row count is 0 after clear', async () => {
    const ctx = makeTestDb()
    const ids = seedMutationFixture(ctx)
    const mutations = createSqliteMutations(ctx.db)

    await mutations.setCategoryAssigned({
      year: 2026,
      month: 4,
      categoryId: ids.catRentId,
      amount: 1000,
    })

    const result = await mutations.clearCategoryAssigned(2026, 4, ids.catRentId)
    expect(result.success).toBe(true)

    const row = ctx.raw
      .prepare('SELECT id FROM monthly_budgets WHERE category_id = ? AND year = ? AND month = ?')
      .get(ids.catRentId, 2026, 4)

    expect(row).toBeUndefined()
  })

  it('is idempotent — returns success: true when no row exists', async () => {
    const ctx = makeTestDb()
    const ids = seedMutationFixture(ctx)
    const mutations = createSqliteMutations(ctx.db)

    // No prior setCategoryAssigned call — should still succeed.
    const result = await mutations.clearCategoryAssigned(2026, 4, ids.catRentId)
    expect(result.success).toBe(true)
  })
})

describe('setCategoryAssigned + getMonthPlan integration', () => {
  it('totalAssigned and readyToAssign reflect the set amount', async () => {
    const ctx = makeTestDb()
    const ids = seedMutationFixture(ctx)
    const mutations = createSqliteMutations(ctx.db)

    await mutations.setCategoryAssigned({
      year: 2026,
      month: 4,
      categoryId: ids.catRentId,
      amount: 1000,
    })
    await mutations.setCategoryAssigned({
      year: 2026,
      month: 4,
      categoryId: ids.catGroceriesId,
      amount: 200,
    })

    const plan = getMonthPlanQuery(ctx.db, 2026, 4)

    // Income from seeded fixture: 3000
    expect(plan.income).toBe(3000)
    expect(plan.totalAssigned).toBe(1200)
    expect(plan.readyToAssign).toBe(1800)

    const rent = plan.groups[0].categories.find((c) => c.id === ids.catRentId)!
    expect(rent.assigned).toBe(1000)

    const groc = plan.groups[0].categories.find((c) => c.id === ids.catGroceriesId)!
    expect(groc.assigned).toBe(200)
  })
})
