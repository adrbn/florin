import { describe, expect, it } from 'vitest'

/**
 * A loan mirror must never carry a category.
 *
 * `getPlan` builds `spent` by summing every categorised row across *all*
 * accounts — it never filters by account kind. The mirror on the loan account
 * holds the opposite sign to the payment it reflects, so the moment it shares
 * the payment's category the two cancel: a 136 € instalment nets to zero, a
 * 929 € one wipes most of its envelope.
 *
 * These tests pin the arithmetic rather than the SQL, because the arithmetic is
 * what went wrong on real data: one instalment surfaced under Rent and the next
 * under nothing, because the create path nulled the category and the update
 * path simply left whatever was already there.
 */

/** The plan's rule, verbatim: expense spend is the negated signed amount. */
function spentFor(
  categoryId: string,
  rows: { categoryId: string | null; amount: number; groupKind: 'expense' | 'income' }[],
): number {
  let spent = 0
  for (const row of rows) {
    if (row.categoryId !== categoryId) continue
    if (row.groupKind !== 'expense') continue
    spent -= row.amount
  }
  return Math.round(spent * 100) / 100
}

const STUDENT_LOANS = 'cat-student-loans'
const RENT = 'cat-rent'

describe('loan mirror category', () => {
  it('leaves the instalment counted when the mirror carries no category', () => {
    const rows = [
      { categoryId: STUDENT_LOANS, amount: -136, groupKind: 'expense' as const },
      // the mirror on the loan account
      { categoryId: null, amount: 136, groupKind: 'expense' as const },
    ]
    expect(spentFor(STUDENT_LOANS, rows)).toBe(136)
  })

  it('cancels the instalment entirely when the mirror shares its category', () => {
    const rows = [
      { categoryId: STUDENT_LOANS, amount: -136, groupKind: 'expense' as const },
      { categoryId: STUDENT_LOANS, amount: 136, groupKind: 'expense' as const },
    ]
    // This is the failure mode, stated plainly: the envelope reads as untouched.
    expect(spentFor(STUDENT_LOANS, rows)).toBe(0)
  })

  it('drains an unrelated envelope when the mirror kept a stale category', () => {
    // What the 31 May row actually did: a mirror still labelled Rent from an
    // earlier edit, sitting in an envelope it has nothing to do with.
    const rows = [
      { categoryId: RENT, amount: -929, groupKind: 'expense' as const },
      { categoryId: RENT, amount: 928.73, groupKind: 'expense' as const },
    ]
    expect(spentFor(RENT, rows)).toBe(0.27)
  })

  it('keeps two months consistent once mirrors are uncategorised', () => {
    const rows = [
      { categoryId: STUDENT_LOANS, amount: -136, groupKind: 'expense' as const },
      { categoryId: null, amount: 136, groupKind: 'expense' as const },
      { categoryId: STUDENT_LOANS, amount: -136, groupKind: 'expense' as const },
      { categoryId: null, amount: 136, groupKind: 'expense' as const },
    ]
    expect(spentFor(STUDENT_LOANS, rows)).toBe(272)
  })
})
