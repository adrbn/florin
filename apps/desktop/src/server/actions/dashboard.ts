'use server'

import { queries } from '@/db/client'

interface SerializedExpense {
  id: string
  payee: string
  date: string
  amount: number
  categoryName: string | null
}

/**
 * Server action wrapper around getTopExpenses for the client-side filter UI
 * on the dashboard's "Top expenses" card. The card boots with a server-rendered
 * default list and re-fetches via this action whenever the user changes the
 * days window or category filter.
 *
 * Serialises `Date` -> ISO date string so the payload is safe for the RSC wire
 * format and matches the component's `SerializedExpense` interface.
 */
export async function fetchTopExpenses(
  days: number,
  categoryId: string | null,
): Promise<ReadonlyArray<SerializedExpense>> {
  // Light input clamping -- UI is internal but cheap defense in depth.
  const safeDays = Math.max(1, Math.min(365, Math.floor(days)))
  const raw = await queries.getTopExpenses(5, safeDays, categoryId)
  return raw.map((e) => ({
    id: e.id,
    payee: e.payee,
    date: e.date.toISOString().slice(0, 10),
    amount: Number(e.amount),
    categoryName: e.categoryName ?? null,
  }))
}
