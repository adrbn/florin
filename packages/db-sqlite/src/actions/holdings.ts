import { eq } from 'drizzle-orm'
import { z } from 'zod'
import type { ActionResult, AddHoldingInput, UpdateHoldingInput } from '@florin/core/types'
import type { SqliteDB } from '../client'
import { holdings } from '../schema'
import { recomputeMarketValue } from './helpers'

// SQLite twin of db-pg/actions/holdings.ts. quantity/costBasis/lastPrice are
// real numbers; lastPriceAt and timestamps are ISO strings.

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
  db: SqliteDB,
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
        quantity: d.quantity,
        costBasis: d.costBasis,
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
  db: SqliteDB,
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
    const set: Record<string, unknown> = { updatedAt: new Date().toISOString() }
    if (d.label !== undefined) set.label = d.label
    if (d.isin !== undefined) set.isin = d.isin
    if (d.quoteSymbol !== undefined) set.quoteSymbol = d.quoteSymbol
    if (d.quantity !== undefined) set.quantity = d.quantity
    if (d.costBasis !== undefined) set.costBasis = d.costBasis
    if (d.currency !== undefined) set.currency = d.currency
    await db.update(holdings).set(set).where(eq(holdings.id, id))
    await recomputeMarketValue(db, existing.accountId)
    return { success: true }
  } catch (error: unknown) {
    return { success: false, error: error instanceof Error ? error.message : 'Failed to update holding' }
  }
}

export async function deleteHoldingMutation(db: SqliteDB, id: string): Promise<ActionResult> {
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

/**
 * Persist a freshly-fetched price onto a holding. Returns the holding's
 * accountId so the refresh loop can recompute market value once per account.
 */
export async function applyHoldingQuoteMutation(
  db: SqliteDB,
  holdingId: string,
  price: number,
  fetchedAtIso: string,
): Promise<string | null> {
  const existing = await db.query.holdings.findFirst({ where: eq(holdings.id, holdingId) })
  if (!existing) return null
  await db
    .update(holdings)
    .set({ lastPrice: price, lastPriceAt: fetchedAtIso, updatedAt: new Date().toISOString() })
    .where(eq(holdings.id, holdingId))
  return existing.accountId
}
