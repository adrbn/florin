'use server'

import { queries } from '@/db/client'
import type { TopSpendMode, TopSpendResult } from '@florin/core/types'

/**
 * Server action backing the dashboard's "Top spend" card. The card boots with
 * a server-rendered default and re-fetches via this action whenever the user
 * changes the mode (transactions/merchants), window, category, count, or the
 * minimum-amount filter. The result is already RSC-serialisable.
 */
export async function fetchTopSpend(params: {
  mode: TopSpendMode
  days: number
  categoryId: string | null
  limit: number
  minAmount: number
}): Promise<TopSpendResult> {
  // Light input clamping -- UI is internal but cheap defense in depth.
  const safeDays = Math.max(1, Math.min(365, Math.floor(params.days)))
  const safeLimit = Math.max(1, Math.min(50, Math.floor(params.limit)))
  const safeMin = Math.max(0, Number.isFinite(params.minAmount) ? params.minAmount : 0)
  const mode: TopSpendMode = params.mode === 'merchants' ? 'merchants' : 'transactions'
  return queries.getTopSpend({
    mode,
    limit: safeLimit,
    days: safeDays,
    categoryId: params.categoryId,
    minAmount: safeMin,
  })
}
