'use server'

import { revalidatePath } from 'next/cache'
import type { ActionResult, PriceRefreshResult } from '@florin/core/types'
import { refreshPriceQuotes as runRefresh } from '@/server/pricing/refresh'

export type { PriceRefreshResult, ActionResult }

/**
 * Manual price-refresh action wired to the HoldingsCard "Refresh prices" button.
 * Wraps the refresh job in the standard ActionResult envelope and revalidates
 * the account/net-worth surfaces so the new market value renders immediately.
 */
export async function refreshPriceQuotes(): Promise<ActionResult<PriceRefreshResult>> {
  try {
    const data = await runRefresh()
    revalidatePath('/accounts')
    revalidatePath('/accounts/[id]', 'page')
    revalidatePath('/')
    return { success: true, data }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Unknown error'
    return { success: false, error: message }
  }
}
