import { eq, sql } from 'drizzle-orm'
import { z } from 'zod'
import { normalizePayee } from '@florin/core/lib/categorization'
import type {
  ActionResult,
  AddHoldingInput,
  BuyHoldingInput,
  UpdateHoldingInput,
} from '@florin/core/types'
import type { PgDB } from '../client'
import { holdings, transactions } from '../schema'
import { recomputeAccountBalance, recomputeMarketValue } from './helpers'

const addSchema = z.object({
  accountId: z.uuid(),
  label: z.string().min(1).max(120),
  isin: z.string().max(20).optional().nullable(),
  quoteSymbol: z.string().max(40).optional().nullable(),
  quantity: z.coerce.number().min(0),
  costBasis: z.coerce.number().min(0),
  currency: z.string().max(8).optional(),
})

export async function addHoldingMutation(
  db: PgDB,
  input: AddHoldingInput,
): Promise<ActionResult<{ id: string }>> {
  const parsed = addSchema.safeParse(input)
  if (!parsed.success) {
    return { success: false, error: parsed.error.issues.map((i) => i.message).join(', ') }
  }
  const d = parsed.data
  try {
    const [row] = await db
      .insert(holdings)
      .values({
        accountId: d.accountId,
        label: d.label,
        isin: d.isin ?? null,
        quoteSymbol: d.quoteSymbol ?? null,
        quantity: String(d.quantity),
        costBasis: d.costBasis.toFixed(2),
        currency: d.currency ?? 'EUR',
      })
      .returning({ id: holdings.id })
    await recomputeMarketValue(db, d.accountId)
    return { success: true, data: { id: row?.id ?? '' } }
  } catch (error: unknown) {
    return { success: false, error: error instanceof Error ? error.message : 'Failed to add holding' }
  }
}

const updateSchema = z.object({
  label: z.string().min(1).max(120).optional(),
  isin: z.string().max(20).optional().nullable(),
  quoteSymbol: z.string().max(40).optional().nullable(),
  quantity: z.coerce.number().min(0).optional(),
  costBasis: z.coerce.number().min(0).optional(),
  currency: z.string().max(8).optional(),
})

export async function updateHoldingMutation(
  db: PgDB,
  id: string,
  input: UpdateHoldingInput,
): Promise<ActionResult> {
  if (!z.uuid().safeParse(id).success) return { success: false, error: 'Invalid holding id' }
  const parsed = updateSchema.safeParse(input)
  if (!parsed.success) {
    return { success: false, error: parsed.error.issues.map((i) => i.message).join(', ') }
  }
  try {
    const existing = await db.query.holdings.findFirst({ where: eq(holdings.id, id) })
    if (!existing) return { success: false, error: 'Holding not found' }
    const d = parsed.data
    const set: Record<string, unknown> = { updatedAt: new Date() }
    if (d.label !== undefined) set.label = d.label
    if (d.isin !== undefined) set.isin = d.isin
    if (d.quoteSymbol !== undefined) set.quoteSymbol = d.quoteSymbol
    if (d.quantity !== undefined) set.quantity = String(d.quantity)
    if (d.costBasis !== undefined) set.costBasis = d.costBasis.toFixed(2)
    if (d.currency !== undefined) set.currency = d.currency
    await db.update(holdings).set(set).where(eq(holdings.id, id))
    await recomputeMarketValue(db, existing.accountId)
    return { success: true }
  } catch (error: unknown) {
    return { success: false, error: error instanceof Error ? error.message : 'Failed to update holding' }
  }
}

export async function deleteHoldingMutation(db: PgDB, id: string): Promise<ActionResult> {
  if (!z.uuid().safeParse(id).success) return { success: false, error: 'Invalid holding id' }
  try {
    const existing = await db.query.holdings.findFirst({ where: eq(holdings.id, id) })
    if (!existing) return { success: true }
    await db.delete(holdings).where(eq(holdings.id, id))
    await recomputeMarketValue(db, existing.accountId)
    return { success: true }
  } catch (error: unknown) {
    return { success: false, error: error instanceof Error ? error.message : 'Failed to delete holding' }
  }
}

const buySchema = z
  .object({
    accountId: z.uuid(),
    holdingId: z.uuid().optional().nullable(),
    label: z.string().min(1).max(120).optional(),
    isin: z.string().max(20).optional().nullable(),
    quoteSymbol: z.string().max(40).optional().nullable(),
    quantity: z.coerce.number().positive(),
    amount: z.coerce.number().positive(),
  })
  .refine((v) => Boolean(v.holdingId) || Boolean(v.label), {
    message: 'Provide an existing holding or a label for a new one',
  })

/**
 * One-click buy: add `quantity` shares for `amount` € to a holding (existing or
 * new), then deduct `amount` from the account's cash by recording a buy
 * transaction. Cash → shares in a single step, no double-counting.
 */
export async function buyHoldingMutation(
  db: PgDB,
  input: BuyHoldingInput,
): Promise<ActionResult<{ holdingId: string }>> {
  const parsed = buySchema.safeParse(input)
  if (!parsed.success) {
    return { success: false, error: parsed.error.issues.map((i) => i.message).join(', ') }
  }
  const d = parsed.data
  try {
    let holdingId = d.holdingId ?? null
    let label = 'titre'
    if (holdingId) {
      const existing = await db.query.holdings.findFirst({ where: eq(holdings.id, holdingId) })
      if (!existing) return { success: false, error: 'Holding not found' }
      label = existing.label
      await db
        .update(holdings)
        .set({
          quantity: sql`${holdings.quantity} + ${d.quantity}`,
          costBasis: sql`${holdings.costBasis} + ${d.amount.toFixed(2)}::numeric`,
          ...(d.quoteSymbol ? { quoteSymbol: d.quoteSymbol } : {}),
          ...(d.isin ? { isin: d.isin } : {}),
          updatedAt: new Date(),
        })
        .where(eq(holdings.id, holdingId))
    } else {
      if (!d.label) return { success: false, error: 'A new holding needs a label' }
      label = d.label
      const [row] = await db
        .insert(holdings)
        .values({
          accountId: d.accountId,
          label: d.label,
          isin: d.isin ?? null,
          quoteSymbol: d.quoteSymbol ?? null,
          quantity: String(d.quantity),
          costBasis: d.amount.toFixed(2),
          currency: 'EUR',
        })
        .returning({ id: holdings.id })
      holdingId = row?.id ?? null
    }

    const payee = `Achat ${label}`
    await db.insert(transactions).values({
      accountId: d.accountId,
      occurredAt: new Date(),
      amount: (-d.amount).toFixed(2),
      payee,
      normalizedPayee: normalizePayee(payee),
      memo: 'auto: achat de titre',
      categoryId: null,
      source: 'manual',
      status: 'cleared',
      needsReview: false,
    })
    await recomputeAccountBalance(db, d.accountId, -d.amount)
    await recomputeMarketValue(db, d.accountId)
    return { success: true, data: { holdingId: holdingId ?? '' } }
  } catch (error: unknown) {
    return { success: false, error: error instanceof Error ? error.message : 'Failed to buy holding' }
  }
}

/**
 * Persist a freshly-fetched price onto a holding. Returns the holding's
 * accountId so the price-refresh loop can recompute that account's market value
 * once, after all its holdings are updated. Does NOT recompute here (batched by
 * the caller). Returns null when the holding no longer exists.
 */
export async function applyHoldingQuoteMutation(
  db: PgDB,
  holdingId: string,
  price: number,
  fetchedAtIso: string,
): Promise<string | null> {
  const existing = await db.query.holdings.findFirst({ where: eq(holdings.id, holdingId) })
  if (!existing) return null
  await db
    .update(holdings)
    .set({ lastPrice: String(price), lastPriceAt: new Date(fetchedAtIso), updatedAt: new Date() })
    .where(eq(holdings.id, holdingId))
  return existing.accountId
}
