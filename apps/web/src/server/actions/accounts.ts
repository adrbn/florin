'use server'

import { revalidatePath } from 'next/cache'
import { mutations, queries } from '@/db/client'
import type {
  ActionResult,
  CreateAccountInput,
  UpdateAccountInput,
  LoanSettingsInput,
} from '@florin/core/types'

export type { CreateAccountInput, UpdateAccountInput, ActionResult }

export async function createAccount(
  input: CreateAccountInput,
): Promise<ActionResult<{ id: string }>> {
  const result = await mutations.createAccount(input)
  if (result.success) {
    revalidatePath('/accounts')
    revalidatePath('/')
  }
  return result
}

export async function updateAccount(input: UpdateAccountInput): Promise<ActionResult> {
  const result = await mutations.updateAccount(input)
  if (result.success) {
    revalidatePath('/accounts')
    revalidatePath('/')
  }
  return result
}

export async function deleteAccount(
  id: string,
  opts?: { deleteTransactions?: boolean },
): Promise<ActionResult> {
  const result = await mutations.deleteAccount(id, opts)
  if (result.success) {
    revalidatePath('/accounts')
    revalidatePath('/')
  }
  return result
}

export async function setAccountArchived(id: string, archived: boolean): Promise<ActionResult> {
  const result = await mutations.setAccountArchived(id, archived)
  if (result.success) {
    revalidatePath('/accounts')
    revalidatePath('/')
    revalidatePath('/transactions')
  }
  return result
}

export async function listAccounts(options: { includeArchived?: boolean } = {}) {
  return queries.listAccounts(options)
}

export async function reorderAccounts(input: { orderedIds: string[] }): Promise<ActionResult> {
  const result = await mutations.reorderAccounts(input.orderedIds)
  if (result.success) {
    revalidatePath('/accounts')
    revalidatePath('/')
  }
  return result
}

export async function mergeAccount(input: {
  sourceId: string
  targetId: string
}): Promise<ActionResult> {
  const result = await mutations.mergeAccount(input.sourceId, input.targetId)
  if (result.success) {
    revalidatePath('/accounts')
    revalidatePath('/transactions')
    revalidatePath('/')
  }
  return result
}

export async function getAccountById(id: string) {
  return queries.getAccountById(id)
}

export type { LoanSettingsInput }

export async function updateLoanSettings(input: LoanSettingsInput): Promise<ActionResult> {
  const result = await mutations.updateLoanSettings(input)
  if (result.success) {
    revalidatePath(`/accounts/${input.id}`)
    revalidatePath('/accounts')
    revalidatePath('/')
  }
  return result
}
