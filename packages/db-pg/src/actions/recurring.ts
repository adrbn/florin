import { randomUUID } from 'node:crypto'
import { and, eq, inArray, sql } from 'drizzle-orm'
import { z } from 'zod'
import { normalizePayee } from '@florin/core/lib/categorization'
import type {
  ActionResult,
  CreateRecurringRuleInput,
  UpdateRecurringRuleInput,
} from '@florin/core/types'
import type { PgDB } from '../client'
import { accounts, recurringRules, transactions } from '../schema'

/** How far ahead to materialize scheduled occurrences. */
const HORIZON_MONTHS = 3

const createSchema = z
  .object({
    name: z.string().min(1).max(120),
    kind: z.enum(['transfer', 'transaction']).default('transfer'),
    accountId: z.uuid(),
    toAccountId: z.uuid().optional().nullable(),
    amount: z.coerce.number().positive(),
    payee: z.string().max(200).optional(),
    categoryId: z.uuid().optional().nullable(),
    currency: z.string().max(8).optional(),
    memo: z.string().max(500).optional().nullable(),
    frequency: z.literal('monthly').default('monthly'),
    interval: z.coerce.number().int().min(1).max(12).optional(),
    dayOfMonth: z.coerce.number().int().min(1).max(31),
    startDate: z.coerce.date(),
    endDate: z.coerce.date().optional().nullable(),
  })
  .refine((v) => v.kind !== 'transfer' || !!v.toAccountId, {
    message: 'A transfer rule needs a destination account',
  })
  .refine((v) => !v.toAccountId || v.toAccountId !== v.accountId, {
    message: 'Source and destination accounts must differ',
  })

export async function createRecurringRuleMutation(
  db: PgDB,
  input: CreateRecurringRuleInput,
): Promise<ActionResult<{ id: string }>> {
  const parsed = createSchema.safeParse(input)
  if (!parsed.success) {
    return { success: false, error: parsed.error.issues.map((i) => i.message).join(', ') }
  }
  const d = parsed.data
  try {
    const [row] = await db
      .insert(recurringRules)
      .values({
        name: d.name,
        kind: d.kind,
        accountId: d.accountId,
        toAccountId: d.toAccountId ?? null,
        amount: d.amount.toFixed(2),
        payee: d.payee ?? '',
        categoryId: d.categoryId ?? null,
        currency: d.currency ?? 'EUR',
        memo: d.memo ?? null,
        frequency: d.frequency,
        interval: d.interval ?? 1,
        dayOfMonth: d.dayOfMonth,
        startDate: d.startDate,
        endDate: d.endDate ?? null,
      })
      .returning({ id: recurringRules.id })
    return { success: true, data: { id: row?.id ?? '' } }
  } catch (error: unknown) {
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Failed to create recurring rule',
    }
  }
}

export async function updateRecurringRuleMutation(
  db: PgDB,
  input: UpdateRecurringRuleInput,
): Promise<ActionResult> {
  const idParse = z.uuid().safeParse(input.id)
  if (!idParse.success) return { success: false, error: 'Invalid rule id' }
  try {
    const set: Record<string, unknown> = { updatedAt: new Date() }
    if (input.name !== undefined) set.name = input.name
    if (input.amount !== undefined) set.amount = Number(input.amount).toFixed(2)
    if (input.dayOfMonth !== undefined) set.dayOfMonth = input.dayOfMonth
    if (input.interval !== undefined) set.interval = input.interval
    if (input.toAccountId !== undefined) set.toAccountId = input.toAccountId
    if (input.categoryId !== undefined) set.categoryId = input.categoryId
    if (input.memo !== undefined) set.memo = input.memo
    if (input.payee !== undefined) set.payee = input.payee
    if (input.currency !== undefined) set.currency = input.currency
    if (input.startDate !== undefined) set.startDate = input.startDate
    if (input.endDate !== undefined) set.endDate = input.endDate
    if (input.isActive !== undefined) set.isActive = input.isActive
    await db.update(recurringRules).set(set).where(eq(recurringRules.id, input.id))
    return { success: true }
  } catch (error: unknown) {
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Failed to update recurring rule',
    }
  }
}

export async function deleteRecurringRuleMutation(
  db: PgDB,
  id: string,
  opts?: { deleteGeneratedScheduled?: boolean },
): Promise<ActionResult> {
  const parsed = z.uuid().safeParse(id)
  if (!parsed.success) return { success: false, error: 'Invalid rule id' }
  try {
    if (opts?.deleteGeneratedScheduled) {
      // Remove only FUTURE scheduled occurrences. Already-cleared (realized)
      // history is never touched. Scheduled rows don't affect realized balance,
      // so no recompute is needed.
      const future = await db
        .select({ id: transactions.id })
        .from(transactions)
        .where(
          and(
            eq(transactions.recurringRuleId, id),
            eq(transactions.status, 'scheduled'),
            sql`${transactions.occurredAt}::date > CURRENT_DATE`,
          ),
        )
      if (future.length > 0) {
        await db.delete(transactions).where(
          inArray(
            transactions.id,
            future.map((r) => r.id),
          ),
        )
      }
    }
    // Remaining generated rows keep their data; recurringRuleId is FK ON DELETE
    // SET NULL, so they simply detach.
    await db.delete(recurringRules).where(eq(recurringRules.id, id))
    return { success: true }
  } catch (error: unknown) {
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Failed to delete recurring rule',
    }
  }
}

function clampDay(year: number, monthIndex: number, day: number): number {
  const last = new Date(Date.UTC(year, monthIndex + 1, 0)).getUTCDate()
  return Math.min(Math.max(1, day), last)
}

/**
 * First occurrence on `dayOfMonth` strictly AFTER `after`. Used to set a rule's
 * startDate to the next period when the user creates a one-off + "repeat" in the
 * same action, so the one-off and the first generated occurrence don't collide.
 */
export function nextMonthlyOccurrenceAfter(after: Date, dayOfMonth: number): Date {
  let y = after.getUTCFullYear()
  let m = after.getUTCMonth()
  const afterMs = Date.UTC(after.getUTCFullYear(), after.getUTCMonth(), after.getUTCDate())
  for (let i = 0; i < 36; i++) {
    const dMs = Date.UTC(y, m, clampDay(y, m, dayOfMonth))
    if (dMs > afterMs) return new Date(dMs)
    m += 1
    if (m >= 12) {
      m = 0
      y += 1
    }
  }
  return after
}

function toUtcMidnight(d: Date): number {
  return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate())
}

async function insertOccurrence(
  db: PgDB,
  rule: typeof recurringRules.$inferSelect,
  d: Date,
  nameById: Map<string, string>,
): Promise<number> {
  const recurrenceKey = `${rule.id}:${d.toISOString().slice(0, 10)}`
  const amount = Math.abs(Number(rule.amount))
  if (rule.kind === 'transfer' && rule.toAccountId) {
    const toName = nameById.get(rule.toAccountId) ?? 'account'
    const fromName = nameById.get(rule.accountId) ?? 'account'
    const outPayee = rule.payee || `Transfer to ${toName}`
    const inPayee = rule.payee || `Transfer from ${fromName}`
    const transferPairId = randomUUID()
    const res = await db
      .insert(transactions)
      .values([
        {
          accountId: rule.accountId,
          occurredAt: d,
          amount: (-amount).toFixed(2),
          payee: outPayee,
          normalizedPayee: normalizePayee(outPayee),
          memo: rule.memo,
          categoryId: null,
          source: 'manual',
          transferPairId,
          needsReview: false,
          status: 'scheduled',
          recurringRuleId: rule.id,
          recurrenceKey,
        },
        {
          accountId: rule.toAccountId,
          occurredAt: d,
          amount: amount.toFixed(2),
          payee: inPayee,
          normalizedPayee: normalizePayee(inPayee),
          memo: rule.memo,
          categoryId: rule.categoryId,
          source: 'manual',
          transferPairId,
          needsReview: false,
          status: 'scheduled',
          recurringRuleId: rule.id,
          recurrenceKey,
        },
      ])
      .onConflictDoNothing()
      .returning({ id: transactions.id })
    return res.length
  }

  const payee = rule.payee || rule.name
  const res = await db
    .insert(transactions)
    .values({
      accountId: rule.accountId,
      occurredAt: d,
      amount: Number(rule.amount).toFixed(2),
      payee,
      normalizedPayee: normalizePayee(payee),
      memo: rule.memo,
      categoryId: rule.categoryId,
      source: 'manual',
      needsReview: false,
      status: 'scheduled',
      recurringRuleId: rule.id,
      recurrenceKey,
    })
    .onConflictDoNothing()
    .returning({ id: transactions.id })
  return res.length
}

/**
 * Materialize scheduled occurrences for every active rule, from max(startDate,
 * today, lastMaterialized+1d) up to today + HORIZON_MONTHS. Idempotent via the
 * (recurrence_key, account_id) unique index + onConflictDoNothing, so it is
 * safe to call on every dashboard load / sync.
 */
export async function materializeScheduledTransactions(
  db: PgDB,
): Promise<ActionResult<{ generated: number }>> {
  try {
    const now = new Date()
    const todayMs = toUtcMidnight(now)
    const horizonMs = Date.UTC(now.getUTCFullYear(), now.getUTCMonth() + HORIZON_MONTHS, now.getUTCDate())

    const rules = await db.select().from(recurringRules).where(eq(recurringRules.isActive, true))
    if (rules.length === 0) return { success: true, data: { generated: 0 } }

    const accs = await db.select({ id: accounts.id, name: accounts.name }).from(accounts)
    const nameById = new Map(accs.map((a) => [a.id, a.name]))

    let generated = 0
    for (const rule of rules) {
      const start = rule.startDate instanceof Date ? rule.startDate : new Date(rule.startDate)
      const end = rule.endDate ? (rule.endDate instanceof Date ? rule.endDate : new Date(rule.endDate)) : null
      const lastMat = rule.lastMaterializedDate
        ? rule.lastMaterializedDate instanceof Date
          ? rule.lastMaterializedDate
          : new Date(rule.lastMaterializedDate)
        : null

      const lowerMs = Math.max(
        toUtcMidnight(start),
        todayMs,
        lastMat ? toUtcMidnight(lastMat) + 86_400_000 : 0,
      )
      const endMs = end ? toUtcMidnight(end) : null
      const interval = Math.max(1, rule.interval || 1)

      const cursor = new Date(lowerMs)
      let y = cursor.getUTCFullYear()
      let m = cursor.getUTCMonth()
      const occ: Date[] = []
      for (let guard = 0; guard < 240; guard++) {
        const dMs = Date.UTC(y, m, clampDay(y, m, rule.dayOfMonth))
        if (dMs > horizonMs) break
        if (dMs >= lowerMs && (endMs === null || dMs <= endMs)) {
          occ.push(new Date(dMs))
        }
        m += interval
        while (m >= 12) {
          m -= 12
          y += 1
        }
      }

      for (const d of occ) {
        generated += await insertOccurrence(db, rule, d, nameById)
      }
      if (occ.length > 0) {
        await db
          .update(recurringRules)
          .set({ lastMaterializedDate: occ[occ.length - 1], updatedAt: new Date() })
          .where(eq(recurringRules.id, rule.id))
      }
    }
    return { success: true, data: { generated } }
  } catch (error: unknown) {
    return {
      success: false,
      error: error instanceof Error ? error.message : 'Failed to materialize scheduled transactions',
    }
  }
}
