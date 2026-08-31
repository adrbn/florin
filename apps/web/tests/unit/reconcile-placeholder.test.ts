import { describe, expect, it } from 'vitest'
import { isPlaceholderOf } from '@florin/core/lib/reconcile'

/**
 * The cases these rules exist for are all drawn from a real ledger: eleven
 * pairs La Banque Postale booked twice over ten weeks, and the near-misses
 * that must NOT be swept up with them.
 */
describe('isPlaceholderOf', () => {
  it('matches the bank re-booking an instant transfer with the counterparty', () => {
    expect(
      isPlaceholderOf('VIREMENT INSTANTANE DEBIT', 'VIREMENT INSTANTANE WERO A PAULINE FERAY'),
    ).toBe(true)
    expect(
      isPlaceholderOf('VIREMENT INSTANTANE CREDIT', 'VIREMENT INSTANTANE DE MME ROBINO AGNES'),
    ).toBe(true)
    expect(
      isPlaceholderOf('VIREMENT INSTANTANE CREDIT', 'VIREMENT INSTANTANE DE Jean Dupont RB'),
    ).toBe(true)
  })

  it('ignores case and accents', () => {
    expect(isPlaceholderOf('virement instantané crédit', 'VIREMENT INSTANTANE DE X Y')).toBe(true)
  })

  it('accepts a bare rail prefix with nothing after it', () => {
    expect(isPlaceholderOf('VIREMENT INSTANTANE', 'VIREMENT INSTANTANE DE MME ROBINO')).toBe(true)
  })

  it('refuses two real purchases that merely share a rail and a merchant', () => {
    // Same amount at the same shop days apart is a thing that happens; the
    // earlier label adds a merchant, not a direction.
    expect(
      isPlaceholderOf('ACHAT CB LECLERC', 'ACHAT CB LECLERC STATION 22.08.26'),
    ).toBe(false)
  })

  it('refuses when the opening words differ', () => {
    expect(isPlaceholderOf('PRELEVEMENT DEBIT', 'VIREMENT INSTANTANE DE X Y')).toBe(false)
  })

  it('refuses when the earlier label is not the shorter one', () => {
    expect(
      isPlaceholderOf('VIREMENT INSTANTANE DE MME ROBINO AGNES', 'VIREMENT INSTANTANE CREDIT'),
    ).toBe(false)
    // Identical labels are not a re-booking either — that is a repeat payment,
    // and the (source, external_id) index already handles a true re-delivery.
    expect(isPlaceholderOf('VIREMENT INSTANTANE CREDIT', 'VIREMENT INSTANTANE CREDIT')).toBe(false)
  })

  it('refuses a label too short to carry a shared prefix', () => {
    expect(isPlaceholderOf('VIREMENT', 'VIREMENT INSTANTANE DE X')).toBe(false)
  })
})
