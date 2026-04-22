import { eq, inArray, sql } from 'drizzle-orm'
import { z } from 'zod'
import type {
  ActionResult,
  CreateAccountInput,
  UpdateAccountInput,
  LoanSettingsInput,
} from '@florin/core/types'
import type { SqliteDB } from '../client'
import { accounts, transactions } from '../schema'

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

export async function createAccountMutation(
  db: SqliteDB,
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
        currentBalance: data.currentBalance,
        // Fresh account → no transactions yet, so the invariant
        // `current = opening + sum(tx)` collapses to `opening = current`.
        openingBalance: data.currentBalance,
        displayIcon: data.displayIcon || null,
        displayColor: data.displayColor || null,
        syncProvider: 'manual',
      })
      .returning({ id: accounts.id })

    return { success: true, data: { id: row?.id ?? '' } }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to create account'
    return { success: false, error: message }
  }
}

export async function updateAccountMutation(
  db: SqliteDB,
  input: UpdateAccountInput,
): Promise<ActionResult> {
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
        currentBalance: data.currentBalance,
        // Adjust the anchor so the invariant `current = opening + sum(tx)`
        // holds after the user's "I want balance = X" edit.
        openingBalance: sql`${data.currentBalance} - COALESCE((
          SELECT SUM(${transactions.amount})
          FROM ${transactions}
          WHERE ${transactions.accountId} = ${data.id}
            AND ${transactions.deletedAt} IS NULL
        ), 0)`,
        displayIcon: data.displayIcon || null,
        displayColor: data.displayColor || null,
        isIncludedInNetWorth: data.isIncludedInNetWorth ?? true,
        updatedAt: new Date().toISOString(),
      })
      .where(eq(accounts.id, data.id))

    return { success: true }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to update account'
    return { success: false, error: message }
  }
}

export async function deleteAccountMutation(
  db: SqliteDB,
  id: string,
  opts?: { deleteTransactions?: boolean },
): Promise<ActionResult> {
  const parsed = z.uuid().safeParse(id)
  if (!parsed.success) {
    return { success: false, error: 'Invalid account id' }
  }

  try {
    if (opts?.deleteTransactions) {
      // Explicitly delete transactions before the account
      db.delete(transactions).where(eq(transactions.accountId, id)).run()
    }
    // With onDelete: 'set null', remaining transactions keep their data
    // but get accountId = NULL — they stay visible in the "all" view.
    await db.delete(accounts).where(eq(accounts.id, id))
    return { success: true }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to delete account'
    return { success: false, error: message }
  }
}

export async function setAccountArchivedMutation(
  db: SqliteDB,
  id: string,
  archived: boolean,
): Promise<ActionResult> {
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
        updatedAt: new Date().toISOString(),
      })
      .where(eq(accounts.id, id))
    return { success: true }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to archive account'
    return { success: false, error: message }
  }
}

const reorderSchema = z.object({
  orderedIds: z.array(z.uuid()).min(1).max(500),
})

export async function reorderAccountsMutation(
  db: SqliteDB,
  orderedIds: string[],
): Promise<ActionResult> {
  const parsed = reorderSchema.safeParse({ orderedIds })
  if (!parsed.success) {
    return { success: false, error: parsed.error.issues.map((i) => i.message).join(', ') }
  }
  const ids = parsed.data.orderedIds
  try {
    const cases = ids.map((id, i) => sql`WHEN ${accounts.id} = ${id} THEN ${i}`)
    await db
      .update(accounts)
      .set({
        displayOrder: sql`CASE ${sql.join(cases, sql.raw(' '))} END`,
        updatedAt: new Date().toISOString(),
      })
      .where(inArray(accounts.id, ids))
    return { success: true }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to reorder accounts'
    return { success: false, error: message }
  }
}

const mergeSchema = z
  .object({
    sourceId: z.uuid(),
    targetId: z.uuid(),
  })
  .refine((d) => d.sourceId !== d.targetId, {
    message: 'Source and target must be different accounts',
  })

export async function mergeAccountMutation(
  db: SqliteDB,
  sourceId: string,
  targetId: string,
): Promise<ActionResult> {
  const parsed = mergeSchema.safeParse({ sourceId, targetId })
  if (!parsed.success) {
    return { success: false, error: parsed.error.issues.map((i) => i.message).join(', ') }
  }

  try {
    // better-sqlite3 transactions must be synchronous — no async/await.
    // Drizzle's SQLite driver supports synchronous .all()/.get()/.run().
    db.transaction((tx) => {
      const [src] = tx.select().from(accounts).where(eq(accounts.id, sourceId)).all()
      const [tgt] = tx.select().from(accounts).where(eq(accounts.id, targetId)).all()
      if (!src) throw new Error('Source account not found')
      if (!tgt) throw new Error('Target account not found')

      tx.update(transactions)
        .set({ accountId: targetId, updatedAt: new Date().toISOString() })
        .where(eq(transactions.accountId, sourceId))
        .run()

      // Keep whichever account's bank connection is active. If the target
      // is already bank-synced, preserve its sync info and balance (which
      // the next sync will refresh). Only copy sync info from the source
      // when the source is the bank-synced one and the target is manual.
      const tgtIsBankSynced = tgt.bankConnectionId !== null
      const srcIsBankSynced = src.bankConnectionId !== null

      tx.update(accounts)
        .set({
          syncProvider: tgtIsBankSynced ? tgt.syncProvider : src.syncProvider,
          syncExternalId: tgtIsBankSynced ? tgt.syncExternalId : src.syncExternalId,
          bankConnectionId: tgtIsBankSynced ? tgt.bankConnectionId : src.bankConnectionId,
          iban: tgt.iban ?? src.iban,
          institution: tgt.institution ?? src.institution,
          lastSyncedAt: tgtIsBankSynced ? tgt.lastSyncedAt : src.lastSyncedAt,
          currentBalance: srcIsBankSynced && !tgtIsBankSynced
            ? src.currentBalance
            : tgt.currentBalance,
          updatedAt: new Date().toISOString(),
        })
        .where(eq(accounts.id, targetId))
        .run()

      tx.update(accounts)
        .set({
          bankConnectionId: null,
          syncExternalId: null,
          syncProvider: 'manual',
          updatedAt: new Date().toISOString(),
        })
        .where(eq(accounts.id, sourceId))
        .run()

      tx.delete(accounts).where(eq(accounts.id, sourceId)).run()
    })

    return { success: true }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to merge accounts'
    return { success: false, error: message }
  }
}

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

export async function updateLoanSettingsMutation(
  db: SqliteDB,
  input: LoanSettingsInput,
): Promise<ActionResult> {
  const parsed = loanSettingsSchema.safeParse(input)
  if (!parsed.success) {
    return { success: false, error: parsed.error.issues.map((i) => i.message).join(', ') }
  }
  const data = parsed.data
  try {
    await db
      .update(accounts)
      .set({
        loanOriginalPrincipal: data.loanOriginalPrincipal,
        loanInterestRate:
          data.loanInterestRatePercent === null ? null : data.loanInterestRatePercent / 100,
        loanStartDate: data.loanStartDate,
        loanTermMonths: data.loanTermMonths,
        loanMonthlyPayment: data.loanMonthlyPayment,
        updatedAt: new Date().toISOString(),
      })
      .where(eq(accounts.id, data.id))
    return { success: true }
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Failed to update loan settings'
    return { success: false, error: message }
  }
}
