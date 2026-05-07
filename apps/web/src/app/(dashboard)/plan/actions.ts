'use server'

import { revalidatePath } from 'next/cache'
import type {
  ActionResult,
  PlanCategoryTransaction,
  SetCategoryAssignedInput,
} from '@florin/core/types'
import { mutations, queries } from '@/db/client'

export async function setCategoryAssignedAction(
  input: SetCategoryAssignedInput,
): Promise<ActionResult> {
  const result = await mutations.setCategoryAssigned(input)
  if (result.success) revalidatePath('/plan')
  return result
}

export async function copyPreviousMonthBudgetsAction(
  year: number,
  month: number,
): Promise<ActionResult<{ copied: number; sourceYear: number; sourceMonth: number }>> {
  const result = await mutations.copyPreviousMonthBudgets(year, month)
  if (result.success) revalidatePath('/plan')
  return result
}

export async function listPlanCategoryTransactionsAction(
  categoryId: string,
  year: number,
  month: number,
): Promise<PlanCategoryTransaction[]> {
  const start = new Date(Date.UTC(year, month - 1, 1))
  const end = new Date(Date.UTC(year, month, 1))
  const rows = await queries.listTransactions({
    categoryId,
    startDate: start.toISOString(),
    endDate: end.toISOString(),
    excludeTransfers: true,
    limit: 1000,
  })
  return rows.map((r) => ({
    id: r.id,
    occurredAt: r.occurredAt instanceof Date ? r.occurredAt.toISOString() : String(r.occurredAt),
    payee: r.payee,
    memo: r.memo,
    amount: typeof r.amount === 'string' ? parseFloat(r.amount) : Number(r.amount),
    currency: r.currency,
  }))
}
