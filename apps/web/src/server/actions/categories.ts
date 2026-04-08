'use server'

import { asc, eq } from 'drizzle-orm'
import { revalidatePath } from 'next/cache'
import { z } from 'zod'
import { db } from '@/db/client'
import { categories, categoryGroups } from '@/db/schema'

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

export type CreateCategoryInput = z.infer<typeof createCategorySchema>
export type UpdateCategoryInput = z.infer<typeof updateCategorySchema>
export type CreateGroupInput = z.infer<typeof createGroupSchema>
export type UpdateGroupInput = z.infer<typeof updateGroupSchema>

export interface ActionResult<T = void> {
  success: boolean
  error?: string
  data?: T
}

export async function createCategory(
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

    revalidatePath('/categories')
    return { success: true, data: { id: row?.id ?? '' } }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to create category'
    return { success: false, error: message }
  }
}

export async function updateCategory(input: UpdateCategoryInput): Promise<ActionResult> {
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
    revalidatePath('/categories')
    revalidatePath('/transactions')
    revalidatePath('/')
    return { success: true }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to update category'
    return { success: false, error: message }
  }
}

export async function deleteCategory(id: string): Promise<ActionResult> {
  const parsed = z.uuid().safeParse(id)
  if (!parsed.success) {
    return { success: false, error: 'Invalid category id' }
  }

  try {
    await db.delete(categories).where(eq(categories.id, id))
    revalidatePath('/categories')
    revalidatePath('/transactions')
    revalidatePath('/')
    return { success: true }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to delete category'
    return { success: false, error: message }
  }
}

/** Create a new category group (income or expense bucket). */
export async function createCategoryGroup(
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
    revalidatePath('/categories')
    return { success: true, data: { id: row?.id ?? '' } }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to create group'
    return { success: false, error: message }
  }
}

export async function updateCategoryGroup(input: UpdateGroupInput): Promise<ActionResult> {
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
    revalidatePath('/categories')
    revalidatePath('/')
    return { success: true }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to update group'
    return { success: false, error: message }
  }
}

export async function deleteCategoryGroup(id: string): Promise<ActionResult> {
  const parsed = z.uuid().safeParse(id)
  if (!parsed.success) {
    return { success: false, error: 'Invalid group id' }
  }
  try {
    await db.delete(categoryGroups).where(eq(categoryGroups.id, id))
    revalidatePath('/categories')
    revalidatePath('/transactions')
    revalidatePath('/')
    return { success: true }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to delete group'
    return { success: false, error: message }
  }
}

export async function listCategoriesByGroup() {
  return db.query.categoryGroups.findMany({
    orderBy: (g) => [asc(g.displayOrder), asc(g.name)],
    with: {
      categories: {
        orderBy: (c) => [asc(c.displayOrder), asc(c.name)],
      },
    },
  })
}

export type CategoryGroupWithCategories = Awaited<ReturnType<typeof listCategoriesByGroup>>[number]
