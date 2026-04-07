'use server'

import { asc, eq } from 'drizzle-orm'
import { revalidatePath } from 'next/cache'
import { z } from 'zod'
import { db } from '@/db/client'
import { categories } from '@/db/schema'

const createCategorySchema = z.object({
  groupId: z.uuid(),
  name: z.string().min(1).max(100),
  emoji: z.string().max(8).optional().nullable(),
  isFixed: z.coerce.boolean().optional(),
})

export type CreateCategoryInput = z.infer<typeof createCategorySchema>

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

export async function deleteCategory(id: string): Promise<ActionResult> {
  const parsed = z.uuid().safeParse(id)
  if (!parsed.success) {
    return { success: false, error: 'Invalid category id' }
  }

  try {
    await db.delete(categories).where(eq(categories.id, id))
    revalidatePath('/categories')
    return { success: true }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to delete category'
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
