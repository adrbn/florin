'use server'

import { revalidatePath } from 'next/cache'
import { mutations, queries } from '@/db/client'
import type {
  ActionResult,
  CreateCategoryInput,
  UpdateCategoryInput,
  CreateGroupInput,
} from '@florin/core/types'

export type { CreateCategoryInput, UpdateCategoryInput, CreateGroupInput }
export type UpdateGroupInput = CreateGroupInput & { id: string }

export interface CategoryActionResult<T = void> {
  success: boolean
  error?: string
  data?: T
}

export async function createCategory(
  input: CreateCategoryInput,
): Promise<ActionResult<{ id: string }>> {
  const result = await mutations.createCategory(input)
  if (result.success) {
    revalidatePath('/categories')
  }
  return result
}

export async function updateCategory(input: UpdateCategoryInput): Promise<ActionResult> {
  const result = await mutations.updateCategory(input)
  if (result.success) {
    revalidatePath('/categories')
    revalidatePath('/transactions')
    revalidatePath('/')
  }
  return result
}

export async function deleteCategory(id: string): Promise<ActionResult> {
  const result = await mutations.deleteCategory(id)
  if (result.success) {
    revalidatePath('/categories')
    revalidatePath('/transactions')
    revalidatePath('/')
  }
  return result
}

export async function createCategoryGroup(
  input: CreateGroupInput,
): Promise<ActionResult<{ id: string }>> {
  const result = await mutations.createCategoryGroup(input)
  if (result.success) {
    revalidatePath('/categories')
  }
  return result
}

export async function updateCategoryGroup(input: UpdateGroupInput): Promise<ActionResult> {
  const result = await mutations.updateCategoryGroup(input)
  if (result.success) {
    revalidatePath('/categories')
    revalidatePath('/')
  }
  return result
}

export async function deleteCategoryGroup(id: string): Promise<ActionResult> {
  const result = await mutations.deleteCategoryGroup(id)
  if (result.success) {
    revalidatePath('/categories')
    revalidatePath('/transactions')
    revalidatePath('/')
  }
  return result
}

export async function listCategoriesByGroup() {
  return queries.listCategoriesByGroup()
}

export type CategoryGroupWithCategories = Awaited<ReturnType<typeof listCategoriesByGroup>>[number]

export async function listCategoriesFlat() {
  return queries.listCategoriesFlat()
}

export async function setCategoryLoanLink(
  input: { categoryId: string; loanAccountId: string | null },
): Promise<ActionResult<{ touched: number }>> {
  const result = await mutations.setCategoryLoanLink(input.categoryId, input.loanAccountId)
  if (result.success) {
    revalidatePath('/categories')
    revalidatePath('/accounts')
    revalidatePath('/transactions')
    revalidatePath('/')
  }
  return result
}
