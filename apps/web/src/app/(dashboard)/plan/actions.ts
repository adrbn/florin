'use server'

import { revalidatePath } from 'next/cache'
import type { ActionResult, SetCategoryAssignedInput } from '@florin/core/types'
import { mutations } from '@/db/client'

export async function setCategoryAssignedAction(
  input: SetCategoryAssignedInput,
): Promise<ActionResult> {
  const result = await mutations.setCategoryAssigned(input)
  if (result.success) revalidatePath('/plan')
  return result
}
