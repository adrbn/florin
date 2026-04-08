'use server'

import { getTopExpenses, type TopExpense } from '@/server/queries/dashboard'

/**
 * Server action wrapper around getTopExpenses for the client-side filter UI
 * on the dashboard's "Top expenses" card. The card boots with a server-rendered
 * default list and re-fetches via this action whenever the user changes the
 * days window or category filter.
 */
export async function fetchTopExpenses(
  days: number,
  categoryId: string | null,
  n = 5,
): Promise<TopExpense[]> {
  // Light input clamping — UI is internal but cheap defense in depth.
  const safeDays = Math.max(1, Math.min(365, Math.floor(days)))
  const safeN = Math.max(1, Math.min(50, Math.floor(n)))
  return getTopExpenses(safeN, safeDays, categoryId)
}
