'use server'

import { asc, eq, inArray, sql } from 'drizzle-orm'
import { revalidatePath } from 'next/cache'
import { z } from 'zod'
import { db } from '@/db/client'
import { accounts, transactions } from '@/db/schema'

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
 * Persist a new drag-and-drop ordering of accounts. `orderedIds` is the full
 * list of account ids in their new desired order — the client sends every
 * account in the bucket it just reordered and we rewrite `display_order` in
 * one shot so there are never gaps or ties.
 *
 * Using a CASE expression + a single UPDATE means the whole change is atomic
 * from the DB's point of view; concurrent readers will see either the old
 * order or the new one, never a half-applied permutation.
 */
const reorderSchema = z.object({
  orderedIds: z.array(z.uuid()).min(1).max(500),
})

export async function reorderAccounts(input: z.infer<typeof reorderSchema>): Promise<ActionResult> {
  const parsed = reorderSchema.safeParse(input)
  if (!parsed.success) {
    return { success: false, error: parsed.error.issues.map((i) => i.message).join(', ') }
  }
  const { orderedIds } = parsed.data
  try {
    // Build a CASE WHEN id=$1 THEN 0 WHEN id=$2 THEN 1 … expression. Drizzle
    // doesn't ship a first-party CASE helper so we inline it via sql``.
    //
    // Both the uuid id param AND the integer position param need explicit
    // casts — postgres.js binds JS values as untyped text by default, so
    // without `::integer` PostgreSQL picks text for the CASE result and the
    // UPDATE fails with "column 'display_order' is of type integer but
    // expression is of type text". Silently. Which is exactly what bit us.
    const cases = orderedIds.map(
      (id, i) => sql`WHEN ${accounts.id} = ${id}::uuid THEN ${i}::integer`,
    )
    await db
      .update(accounts)
      .set({
        displayOrder: sql`CASE ${sql.join(cases, sql.raw(' '))} END`,
        updatedAt: new Date(),
      })
      .where(inArray(accounts.id, orderedIds))
    revalidatePath('/accounts')
    revalidatePath('/')
    return { success: true }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to reorder accounts'
    console.error('[reorderAccounts] failed', { orderedIds, error: message })
    return { success: false, error: message }
  }
}

/**
 * Merge `sourceId` into `targetId`: re-parents every transaction onto the
 * target, moves the bank-sync identity (provider, external id, connection,
 * iban, institution, last-synced, current balance) from source to target,
 * then drops the now-empty source account. Atomic — either the whole merge
 * commits or none of it does.
 *
 * Use case: legacy CCP (xlsx history) + newly Enable-Banking-synced "La
 * Banque Postale ·3546" (same real-world account). Merging puts all
 * history on CCP and moves the live sync onto CCP so future pushes from
 * the bank API land on the single long-lived account.
 *
 * Cosmetic fields (name, kind, currency, display color/icon/order,
 * archive/net-worth flags) are left as the target had them — the user
 * chose that account as the keeper, so we don't overwrite its identity.
 */
const mergeSchema = z
  .object({
    sourceId: z.uuid(),
    targetId: z.uuid(),
  })
  .refine((d) => d.sourceId !== d.targetId, {
    message: 'Source and target must be different accounts',
  })

export async function mergeAccount(input: z.infer<typeof mergeSchema>): Promise<ActionResult> {
  const parsed = mergeSchema.safeParse(input)
  if (!parsed.success) {
    return { success: false, error: parsed.error.issues.map((i) => i.message).join(', ') }
  }
  const { sourceId, targetId } = parsed.data

  try {
    await db.transaction(async (tx) => {
      const [src] = await tx.select().from(accounts).where(eq(accounts.id, sourceId))
      const [tgt] = await tx.select().from(accounts).where(eq(accounts.id, targetId))
      if (!src) throw new Error('Source account not found')
      if (!tgt) throw new Error('Target account not found')

      // 1. Re-parent every transaction. Unique indexes on (source, externalId)
      //    and legacyId are preserved — we're only touching accountId.
      await tx
        .update(transactions)
        .set({ accountId: targetId, updatedAt: new Date() })
        .where(eq(transactions.accountId, sourceId))

      // 2. Move the live bank-sync identity onto the target so future syncs
      //    land on the keeper. Fill null fields from source; leave cosmetic
      //    fields (name, kind, etc.) alone.
      await tx
        .update(accounts)
        .set({
          syncProvider: src.syncProvider,
          syncExternalId: src.syncExternalId,
          bankConnectionId: src.bankConnectionId,
          iban: tgt.iban ?? src.iban,
          institution: tgt.institution ?? src.institution,
          lastSyncedAt: src.lastSyncedAt,
          // Source is the bank-authoritative balance — use it so the
          // headline number matches reality post-merge.
          currentBalance: src.currentBalance,
          updatedAt: new Date(),
        })
        .where(eq(accounts.id, targetId))

      // 3. Clear source's sync identity before deleting so there's no stale
      //    pointer on the bank connection, then drop the now-empty row.
      await tx
        .update(accounts)
        .set({
          bankConnectionId: null,
          syncExternalId: null,
          syncProvider: 'manual',
          updatedAt: new Date(),
        })
        .where(eq(accounts.id, sourceId))
      await tx.delete(accounts).where(eq(accounts.id, sourceId))
    })

    revalidatePath('/accounts')
    revalidatePath('/transactions')
    revalidatePath('/')
    return { success: true }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to merge accounts'
    return { success: false, error: message }
  }
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

/**
 * Save loan-specific fields for a kind='loan' account. All fields are
 * optional because the user may fill them in over time — we only require
 * the id. The amortization helper does its own "do you have enough to
 * compute a schedule?" check on the UI side, so missing values here just
 * mean "don't render the schedule yet", not a validation error.
 *
 * `interestRate` comes in as a percentage (e.g. 3.5 for 3.5%) from the UI
 * and we store it as a decimal (0.035) — one single conversion point so
 * the rest of the codebase never has to think about the unit.
 */
const loanSettingsSchema = z.object({
  id: z.uuid(),
  loanOriginalPrincipal: z.coerce.number().min(0).nullable(),
  loanInterestRatePercent: z.coerce.number().min(0).max(100).nullable(),
  loanStartDate: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/)
    .nullable(),
  loanTermMonths: z.coerce.number().int().min(1).max(600).nullable(),
  loanMonthlyPayment: z.coerce.number().min(0).nullable(),
})

export type LoanSettingsInput = z.infer<typeof loanSettingsSchema>

export async function updateLoanSettings(input: LoanSettingsInput): Promise<ActionResult> {
  const parsed = loanSettingsSchema.safeParse(input)
  if (!parsed.success) {
    return { success: false, error: parsed.error.issues.map((i) => i.message).join(', ') }
  }
  const data = parsed.data
  try {
    await db
      .update(accounts)
      .set({
        loanOriginalPrincipal:
          data.loanOriginalPrincipal === null ? null : data.loanOriginalPrincipal.toFixed(2),
        loanInterestRate:
          data.loanInterestRatePercent === null
            ? null
            : (data.loanInterestRatePercent / 100).toFixed(6),
        loanStartDate:
          data.loanStartDate === null ? null : new Date(`${data.loanStartDate}T00:00:00Z`),
        loanTermMonths: data.loanTermMonths,
        loanMonthlyPayment:
          data.loanMonthlyPayment === null ? null : data.loanMonthlyPayment.toFixed(2),
        updatedAt: new Date(),
      })
      .where(eq(accounts.id, data.id))
    revalidatePath(`/accounts/${data.id}`)
    revalidatePath('/accounts')
    revalidatePath('/')
    return { success: true }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to update loan settings'
    return { success: false, error: message }
  }
}
