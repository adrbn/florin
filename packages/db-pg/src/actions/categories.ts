import { eq } from 'drizzle-orm'
import { z } from 'zod'
import type {
  ActionResult,
  CreateCategoryInput,
  UpdateCategoryInput,
  CreateGroupInput,
} from '@florin/core/types'
import type { PgDB } from '../client'
import { accounts, categories, categoryGroups } from '../schema'
import { reconcileLoanMirrorsForCategory } from './helpers'

const createCategorySchema = z.object({
  groupId: z.uuid(),
  name: z.string().min(1).max(100),
  emoji: z.string().max(8).optional().nullable(),
  isFixed: z.coerce.boolean().optional(),
})

const updateCategorySchema = z.object({
  id: z.uuid(),
  name: z.string().min(1).max(100),
  emoji: z.string().max(8).optional().nullable(),
  isFixed: z.coerce.boolean().optional(),
})

const createGroupSchema = z.object({
  name: z.string().min(1).max(100),
  kind: z.enum(['income', 'expense']),
  color: z.string().max(16).optional().nullable(),
})

const updateGroupSchema = createGroupSchema.extend({ id: z.uuid() })

export async function createCategoryMutation(
  db: PgDB,
  input: CreateCategoryInput,
): Promise<ActionResult<{ id: string }>> {
  const parsed = createCategorySchema.safeParse(input)
  if (!parsed.success) {
    return {
      success: false,
      error: parsed.error.issues.map((i) => i.message).join(', '),
    }
  }
  const data = parsed.data

  try {
    const [row] = await db
      .insert(categories)
      .values({
        groupId: data.groupId,
        name: data.name,
        emoji: data.emoji || null,
        isFixed: data.isFixed ?? false,
      })
      .returning({ id: categories.id })

    return { success: true, data: { id: row?.id ?? '' } }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to create category'
    return { success: false, error: message }
  }
}

export async function updateCategoryMutation(
  db: PgDB,
  input: UpdateCategoryInput,
): Promise<ActionResult> {
  const parsed = updateCategorySchema.safeParse(input)
  if (!parsed.success) {
    return { success: false, error: parsed.error.issues.map((i) => i.message).join(', ') }
  }
  const data = parsed.data
  try {
    await db
      .update(categories)
      .set({
        name: data.name,
        emoji: data.emoji || null,
        isFixed: data.isFixed ?? false,
      })
      .where(eq(categories.id, data.id))
    return { success: true }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to update category'
    return { success: false, error: message }
  }
}

export async function deleteCategoryMutation(
  db: PgDB,
  id: string,
): Promise<ActionResult> {
  const parsed = z.uuid().safeParse(id)
  if (!parsed.success) {
    return { success: false, error: 'Invalid category id' }
  }

  try {
    await db.delete(categories).where(eq(categories.id, id))
    return { success: true }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to delete category'
    return { success: false, error: message }
  }
}

export async function createCategoryGroupMutation(
  db: PgDB,
  input: CreateGroupInput,
): Promise<ActionResult<{ id: string }>> {
  const parsed = createGroupSchema.safeParse(input)
  if (!parsed.success) {
    return { success: false, error: parsed.error.issues.map((i) => i.message).join(', ') }
  }
  const data = parsed.data
  try {
    const [row] = await db
      .insert(categoryGroups)
      .values({ name: data.name, kind: data.kind, color: data.color || null })
      .returning({ id: categoryGroups.id })
    return { success: true, data: { id: row?.id ?? '' } }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to create group'
    return { success: false, error: message }
  }
}

export async function updateCategoryGroupMutation(
  db: PgDB,
  input: CreateGroupInput & { id: string },
): Promise<ActionResult> {
  const parsed = updateGroupSchema.safeParse(input)
  if (!parsed.success) {
    return { success: false, error: parsed.error.issues.map((i) => i.message).join(', ') }
  }
  const data = parsed.data
  try {
    await db
      .update(categoryGroups)
      .set({ name: data.name, kind: data.kind, color: data.color || null })
      .where(eq(categoryGroups.id, data.id))
    return { success: true }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to update group'
    return { success: false, error: message }
  }
}

export async function deleteCategoryGroupMutation(
  db: PgDB,
  id: string,
): Promise<ActionResult> {
  const parsed = z.uuid().safeParse(id)
  if (!parsed.success) {
    return { success: false, error: 'Invalid group id' }
  }
  try {
    await db.delete(categoryGroups).where(eq(categoryGroups.id, id))
    return { success: true }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to delete group'
    return { success: false, error: message }
  }
}

const setCategoryLoanLinkSchema = z.object({
  categoryId: z.uuid(),
  loanAccountId: z.uuid().nullable(),
})

export async function setCategoryLoanLinkMutation(
  db: PgDB,
  categoryId: string,
  loanAccountId: string | null,
): Promise<ActionResult<{ touched: number }>> {
  const parsed = setCategoryLoanLinkSchema.safeParse({ categoryId, loanAccountId })
  if (!parsed.success) {
    return { success: false, error: parsed.error.issues.map((i) => i.message).join(', ') }
  }

  try {
    if (loanAccountId) {
      const target = await db.query.accounts.findFirst({
        where: eq(accounts.id, loanAccountId),
      })
      if (!target) return { success: false, error: 'Loan account not found' }
      if (target.kind !== 'loan') {
        return { success: false, error: 'Target account is not a loan account' }
      }
    }

    await db
      .update(categories)
      .set({ linkedLoanAccountId: loanAccountId })
      .where(eq(categories.id, categoryId))

    const touched = await reconcileLoanMirrorsForCategory(db, categoryId)

    return { success: true, data: { touched } }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to link category'
    return { success: false, error: message }
  }
}
