'use server'

import { revalidatePath } from 'next/cache'
import { mutations } from '@/db/client'
import type {
  ActionResult,
  AddHoldingInput,
  UpdateHoldingInput,
} from '@florin/core/types'

export type { AddHoldingInput, UpdateHoldingInput, ActionResult }

/**
 * Revalidate every surface a holding change can move: the account detail page,
 * the accounts list, and the dashboard/net-worth root.
 */
function revalidateHoldingSurfaces(): void {
  revalidatePath('/accounts')
  revalidatePath('/accounts/[id]', 'page')
  revalidatePath('/')
}

export async function addHolding(
  input: AddHoldingInput,
): Promise<ActionResult<{ id: string }>> {
  const result = await mutations.addHolding(input)
  if (result.success) {
    revalidateHoldingSurfaces()
  }
  return result
}

export async function updateHolding(
  id: string,
  input: UpdateHoldingInput,
): Promise<ActionResult> {
  const result = await mutations.updateHolding(id, input)
  if (result.success) {
    revalidateHoldingSurfaces()
  }
  return result
}

export async function deleteHolding(id: string): Promise<ActionResult> {
  const result = await mutations.deleteHolding(id)
  if (result.success) {
    revalidateHoldingSurfaces()
  }
  return result
}
