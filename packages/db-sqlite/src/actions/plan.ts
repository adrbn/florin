import { and, eq } from 'drizzle-orm'
import { z } from 'zod'
import type { ActionResult, SetCategoryAssignedInput } from '@florin/core/types'
import type { SqliteDB } from '../client'
import { categories, monthlyBudgets } from '../schema'

const setAssignedSchema = z.object({
  year: z.number().int().min(1970).max(2100),
  month: z.number().int().min(1).max(12),
  categoryId: z.uuid(),
  amount: z.number().min(0).max(99_999_999.99),
  note: z.string().max(500).optional().nullable(),
})

export async function setCategoryAssignedMutation(
  db: SqliteDB,
  input: SetCategoryAssignedInput,
): Promise<ActionResult> {
  const parsed = setAssignedSchema.safeParse(input)
  if (!parsed.success) {
    return {
      success: false,
      error: parsed.error.issues.map((i) => i.message).join(', '),
    }
  }

  const data = parsed.data

  // Determine note intent from the *raw* input before Zod strips undefined keys.
  // - note absent or undefined → preserve existing (PATCH semantics)
  // - note: null               → clear explicitly
  // - note: string             → set new value
  const noteProvided = 'note' in input && input.note !== undefined

  try {
    // Verify the category exists.
    const category = await db.query.categories.findFirst({
      where: eq(categories.id, data.categoryId),
    })
    if (!category) {
      return { success: false, error: 'Category not found' }
    }

    if (noteProvided) {
      // Insert or update — always overwrite note.
      await db
        .insert(monthlyBudgets)
        .values({
          year: data.year,
          month: data.month,
          categoryId: data.categoryId,
          assigned: data.amount,
          note: data.note ?? null,
        })
        .onConflictDoUpdate({
          target: [monthlyBudgets.year, monthlyBudgets.month, monthlyBudgets.categoryId],
          set: {
            assigned: data.amount,
            note: data.note ?? null,
            updatedAt: new Date().toISOString(),
          },
        })
    } else {
      // Insert or update — preserve existing note.
      await db
        .insert(monthlyBudgets)
        .values({
          year: data.year,
          month: data.month,
          categoryId: data.categoryId,
          assigned: data.amount,
          note: null,
        })
        .onConflictDoUpdate({
          target: [monthlyBudgets.year, monthlyBudgets.month, monthlyBudgets.categoryId],
          set: {
            assigned: data.amount,
            updatedAt: new Date().toISOString(),
          },
        })
    }

    return { success: true }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to set assigned amount'
    return { success: false, error: message }
  }
}

const clearAssignedSchema = z.object({
  year: z.number().int().min(1970).max(2100),
  month: z.number().int().min(1).max(12),
  categoryId: z.uuid(),
})

export async function clearCategoryAssignedMutation(
  db: SqliteDB,
  year: number,
  month: number,
  categoryId: string,
): Promise<ActionResult> {
  const parsed = clearAssignedSchema.safeParse({ year, month, categoryId })
  if (!parsed.success) {
    return { success: false, error: parsed.error.issues.map((i) => i.message).join(', ') }
  }

  try {
    await db
      .delete(monthlyBudgets)
      .where(
        and(
          eq(monthlyBudgets.year, year),
          eq(monthlyBudgets.month, month),
          eq(monthlyBudgets.categoryId, categoryId),
        ),
      )

    // Idempotent — success regardless of whether a row was deleted.
    return { success: true }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to clear assigned amount'
    return { success: false, error: message }
  }
}
