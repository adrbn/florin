'use server'

import { revalidatePath } from 'next/cache'
import { mutations, queries, db } from '@/db/client'
import {
  listTransactionsForAccountQuery,
  listLoanPaymentsForAccountQuery,
  reconcileLoanMirrorsForCategory,
} from '@florin/db-sqlite'
import type {
  ActionResult,
  AddTransactionInput,
  AddTransferInput,
  ListTransactionsOptions,
  TransactionDirection,
} from '@florin/core/types'

export type {
  AddTransactionInput,
  AddTransferInput,
  ActionResult,
  TransactionDirection,
  ListTransactionsOptions,
}

export async function addTransaction(
  input: AddTransactionInput,
): Promise<ActionResult<{ id: string }>> {
  const result = await mutations.addTransaction(input)
  if (result.success) {
    revalidatePath('/transactions')
    revalidatePath('/accounts')
    revalidatePath('/')
  }
  return result
}

export async function addTransfer(
  input: AddTransferInput,
): Promise<ActionResult<{ transferPairId: string }>> {
  const result = await mutations.addTransfer(input)
  if (result.success) {
    revalidatePath('/transactions')
    revalidatePath('/accounts')
    revalidatePath('/')
  }
  return result
}

export async function linkAsInternalTransfer(
  transactionId: string,
  counterpartAccountId: string,
): Promise<ActionResult<{ transferPairId: string; mode: 'paired' | 'created' }>> {
  const result = await mutations.linkAsInternalTransfer(transactionId, counterpartAccountId)
  if (result.success) {
    revalidatePath('/review')
    revalidatePath('/transactions')
    revalidatePath('/accounts')
    revalidatePath('/')
  }
  return result
}

export async function countTransactions(options: ListTransactionsOptions = {}): Promise<number> {
  return queries.countTransactions(options)
}

export async function listTransactions(options: ListTransactionsOptions = {}) {
  return queries.listTransactions(options)
}

export async function countNeedsReview(): Promise<number> {
  return queries.countNeedsReview()
}

export async function approveTransaction(transactionId: string): Promise<ActionResult> {
  const result = await mutations.approveTransaction(transactionId)
  if (result.success) {
    revalidatePath('/review')
    revalidatePath('/transactions')
    revalidatePath('/')
  }
  return result
}

export async function approveAllTransactions(): Promise<ActionResult<{ approved: number }>> {
  const result = await mutations.approveAllTransactions()
  if (result.success) {
    revalidatePath('/review')
    revalidatePath('/transactions')
    revalidatePath('/')
  }
  return result
}

export async function listTransactionsForAccount(
  accountId: string,
  limit = 500,
): Promise<TransactionWithRelations[]> {
  return listTransactionsForAccountQuery(db, accountId, limit) as unknown as Promise<TransactionWithRelations[]>
}

export async function listLoanPaymentsForAccount(
  loanAccountId: string,
  limit = 500,
): Promise<TransactionWithRelations[]> {
  return listLoanPaymentsForAccountQuery(db, loanAccountId, limit) as unknown as Promise<TransactionWithRelations[]>
}

export type TransactionWithRelations = Awaited<ReturnType<typeof listTransactions>>[number]

export async function updateTransactionCategory(
  transactionId: string,
  categoryId: string | null,
): Promise<ActionResult> {
  const result = await mutations.updateTransactionCategory(transactionId, categoryId)
  if (result.success) {
    revalidatePath('/transactions')
    revalidatePath('/review')
    revalidatePath('/accounts')
    revalidatePath('/')
    revalidatePath('/categories')
  }
  return result
}

export async function softDeleteTransaction(id: string): Promise<ActionResult> {
  const result = await mutations.softDeleteTransaction(id)
  if (result.success) {
    revalidatePath('/transactions')
    revalidatePath('/review')
    revalidatePath('/accounts')
    revalidatePath('/')
  }
  return result
}

// ============ bulk actions ============

export async function bulkUpdateTransactionCategory(
  ids: ReadonlyArray<string>,
  categoryId: string | null,
): Promise<ActionResult<{ updated: number }>> {
  const result = await mutations.bulkUpdateTransactionCategory([...ids], categoryId)
  if (result.success) {
    revalidatePath('/transactions')
    revalidatePath('/review')
    revalidatePath('/accounts')
    revalidatePath('/')
    revalidatePath('/categories')
  }
  return result
}

export async function bulkApproveTransactions(
  ids: ReadonlyArray<string>,
): Promise<ActionResult<{ approved: number }>> {
  const result = await mutations.bulkApproveTransactions([...ids])
  if (result.success) {
    revalidatePath('/review')
    revalidatePath('/transactions')
    revalidatePath('/')
  }
  return result
}

export async function bulkSoftDeleteTransactions(
  ids: ReadonlyArray<string>,
): Promise<ActionResult<{ deleted: number }>> {
  const result = await mutations.bulkSoftDeleteTransactions([...ids])
  if (result.success) {
    revalidatePath('/transactions')
    revalidatePath('/review')
    revalidatePath('/accounts')
    revalidatePath('/')
  }
  return result
}

/**
 * Exported so the category-link action can back-fill mirrors.
 */
export async function reconcileLoanMirrorsForCategoryAction(
  categoryId: string,
): Promise<number> {
  return reconcileLoanMirrorsForCategory(db, categoryId)
}
