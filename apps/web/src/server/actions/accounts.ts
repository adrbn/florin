'use server'

import { asc, eq } from 'drizzle-orm'
import { revalidatePath } from 'next/cache'
import { z } from 'zod'
import { db } from '@/db/client'
import { accounts } from '@/db/schema'

const accountKindEnum = z.enum([
  'checking',
  'savings',
  'cash',
  'loan',
  'broker_cash',
  'broker_portfolio',
  'other',
])

const createAccountSchema = z.object({
  name: z.string().min(1).max(100),
  kind: accountKindEnum,
  institution: z.string().max(100).optional().nullable(),
  currentBalance: z.coerce.number(),
  displayIcon: z.string().max(8).optional().nullable(),
  displayColor: z.string().max(16).optional().nullable(),
})

const updateAccountSchema = createAccountSchema.extend({
  id: z.uuid(),
  isIncludedInNetWorth: z.coerce.boolean().optional(),
})

export type CreateAccountInput = z.infer<typeof createAccountSchema>
export type UpdateAccountInput = z.infer<typeof updateAccountSchema>

export interface ActionResult<T = void> {
  success: boolean
  error?: string
  data?: T
}

export async function createAccount(
  input: CreateAccountInput,
): Promise<ActionResult<{ id: string }>> {
  const parsed = createAccountSchema.safeParse(input)
  if (!parsed.success) {
    return { success: false, error: parsed.error.issues.map((i) => i.message).join(', ') }
  }
  const data = parsed.data

  try {
    const [row] = await db
      .insert(accounts)
      .values({
        name: data.name,
        kind: data.kind,
        institution: data.institution || null,
        currentBalance: data.currentBalance.toFixed(2),
        displayIcon: data.displayIcon || null,
        displayColor: data.displayColor || null,
        syncProvider: 'manual',
      })
      .returning({ id: accounts.id })

    revalidatePath('/accounts')
    revalidatePath('/')

    return { success: true, data: { id: row?.id ?? '' } }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to create account'
    return { success: false, error: message }
  }
}

export async function updateAccount(input: UpdateAccountInput): Promise<ActionResult> {
  const parsed = updateAccountSchema.safeParse(input)
  if (!parsed.success) {
    return { success: false, error: parsed.error.issues.map((i) => i.message).join(', ') }
  }
  const data = parsed.data

  try {
    await db
      .update(accounts)
      .set({
        name: data.name,
        kind: data.kind,
        institution: data.institution || null,
        currentBalance: data.currentBalance.toFixed(2),
        displayIcon: data.displayIcon || null,
        displayColor: data.displayColor || null,
        isIncludedInNetWorth: data.isIncludedInNetWorth ?? true,
        updatedAt: new Date(),
      })
      .where(eq(accounts.id, data.id))

    revalidatePath('/accounts')
    revalidatePath('/')
    return { success: true }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to update account'
    return { success: false, error: message }
  }
}

export async function deleteAccount(id: string): Promise<ActionResult> {
  const parsed = z.uuid().safeParse(id)
  if (!parsed.success) {
    return { success: false, error: 'Invalid account id' }
  }

  try {
    await db.delete(accounts).where(eq(accounts.id, id))
    revalidatePath('/accounts')
    revalidatePath('/')
    return { success: true }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to delete account'
    return { success: false, error: message }
  }
}

/**
 * Archive or unarchive an account. Archived accounts stay in the DB with all
 * their transactions, but are hidden from the main accounts grid, excluded
 * from net worth, and not offered in pickers. This is the safe way to retire
 * a legacy/duplicated account without losing history.
 */
export async function setAccountArchived(id: string, archived: boolean): Promise<ActionResult> {
  const parsed = z.uuid().safeParse(id)
  if (!parsed.success) {
    return { success: false, error: 'Invalid account id' }
  }
  try {
    await db
      .update(accounts)
      .set({
        isArchived: archived,
        isIncludedInNetWorth: archived ? false : true,
        updatedAt: new Date(),
      })
      .where(eq(accounts.id, id))
    revalidatePath('/accounts')
    revalidatePath('/')
    revalidatePath('/transactions')
    return { success: true }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to archive account'
    return { success: false, error: message }
  }
}

/**
 * List accounts. By default hides archived rows — pass `includeArchived` from
 * the settings/management UI when you want to see everything.
 */
export async function listAccounts(options: { includeArchived?: boolean } = {}) {
  const where = options.includeArchived ? undefined : eq(accounts.isArchived, false)
  const query = db.select().from(accounts).orderBy(asc(accounts.displayOrder), asc(accounts.name))
  return where ? query.where(where) : query
}

/**
 * Fetch a single account row, or null if not found. Used by the
 * `/accounts/[id]` detail page.
 */
export async function getAccountById(id: string) {
  const parsed = z.uuid().safeParse(id)
  if (!parsed.success) return null
  const row = await db.query.accounts.findFirst({
    where: eq(accounts.id, id),
    with: {
      bankConnection: true,
    },
  })
  return row ?? null
}
