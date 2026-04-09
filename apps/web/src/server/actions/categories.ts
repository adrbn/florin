'use server'

import { asc, eq } from 'drizzle-orm'
import { revalidatePath } from 'next/cache'
import { z } from 'zod'
import { db } from '@/db/client'
import { accounts, categories, categoryGroups } from '@/db/schema'
import { reconcileLoanMirrorsForCategory } from '@/server/actions/transactions'

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

/**
 * Plain flat list of (id, name, groupName) for category pickers that don't
 * need the group hierarchy. Used by the loan-details card to pick which
 * category should auto-pay-down the loan.
 */
export async function listCategoriesFlat() {
  return db
    .select({
      id: categories.id,
      name: categories.name,
      emoji: categories.emoji,
      groupName: categoryGroups.name,
      linkedLoanAccountId: categories.linkedLoanAccountId,
    })
    .from(categories)
    .innerJoin(categoryGroups, eq(categories.groupId, categoryGroups.id))
    .orderBy(asc(categoryGroups.name), asc(categories.name))
}

/**
 * Set (or clear) the loan-account link for a single category. Used by the
 * loan details card to say "transactions in category X should pay down this
 * loan". Passing `loanAccountId = null` clears the link.
 *
 * After flipping the link, we walk every non-deleted transaction on this
 * category and re-run the loan-mirror reconciliation so existing history
 * is back-filled — i.e. if the user sets "Student loans" as linked to the
 * loan account for the first time after 6 months of payments, those 6
 * months of mirrors get created retroactively, and the loan balance drops
 * to match reality in one click.
 */
const setCategoryLoanLinkSchema = z.object({
  categoryId: z.uuid(),
  loanAccountId: z.uuid().nullable(),
})

export async function setCategoryLoanLink(
  input: z.infer<typeof setCategoryLoanLinkSchema>,
): Promise<ActionResult<{ touched: number }>> {
  const parsed = setCategoryLoanLinkSchema.safeParse(input)
  if (!parsed.success) {
    return { success: false, error: parsed.error.issues.map((i) => i.message).join(', ') }
  }
  const { categoryId, loanAccountId } = parsed.data

  try {
    // Guard: the target must actually be a loan account, otherwise we'd
    // cheerfully mirror payments onto a checking account and wreck its balance.
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

    // Back-fill: reconcile every non-deleted transaction in this category.
    // This is how "I just set the link, now catch up on the last 6 months
    // of payments" works. Delegates to the same syncLoanMirror used by the
    // transactions actions file.
    const touched = await reconcileLoanMirrorsForCategory(categoryId)

    revalidatePath('/categories')
    revalidatePath('/accounts')
    revalidatePath('/transactions')
    revalidatePath('/')
    return { success: true, data: { touched } }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to link category'
    return { success: false, error: message }
  }
}
