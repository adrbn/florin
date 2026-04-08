'use server'

import { and, eq, inArray } from 'drizzle-orm'
import { revalidatePath } from 'next/cache'
import { redirect } from 'next/navigation'
import { z } from 'zod'
import { db } from '@/db/client'
import { accounts, bankConnections, transactions } from '@/db/schema'
import {
  createSession,
  deleteSession,
  EnableBankingError,
  isEnableBankingConfigured,
  listAspsps as listAspspsApi,
  startAuth,
} from '@/server/banking/enable-banking'
import { encodeAuthState } from '@/server/banking/state'
import { syncConnection as runSync } from '@/server/banking/sync'
import { syncAllConnections } from '@/server/banking/sync-all'
import type { Aspsp } from '@/server/banking/types'
import { env } from '@/server/env'

export interface ActionResult<T = void> {
  success: boolean
  error?: string
  data?: T
}

/**
 * Cap the consent at the lesser of (bank max, 180 days). Most EU banks allow
 * 90 or 180 days under PSD2 — going past that is wasted bytes.
 */
function consentValidUntil(maxDays?: number): string {
  const days = Math.min(maxDays ?? 180, 180)
  return new Date(Date.now() + days * 24 * 60 * 60 * 1000).toISOString()
}

/** List banks for a given country (defaults to FR). Used by the Connect page. */
export async function listBanks(country = 'FR'): Promise<ActionResult<ReadonlyArray<Aspsp>>> {
  if (!isEnableBankingConfigured()) {
    return { success: false, error: 'Enable Banking is not configured.' }
  }
  try {
    const { aspsps } = await listAspspsApi(country)
    // Sort alphabetically and put La Banque Postale first because that's the
    // bank Florin's primary user actually uses — saves a scroll on every visit.
    const sorted = [...aspsps].sort((a, b) => a.name.localeCompare(b.name))
    const lbpIdx = sorted.findIndex((a) => a.name === 'La Banque Postale')
    if (lbpIdx > 0) {
      const lbp = sorted[lbpIdx]
      if (lbp) {
        sorted.splice(lbpIdx, 1)
        sorted.unshift(lbp)
      }
    }
    return { success: true, data: sorted }
  } catch (error: unknown) {
    return { success: false, error: extractErrorMessage(error) }
  }
}

const startSchema = z.object({
  aspspName: z.string().min(1),
  aspspCountry: z.string().min(2).max(2),
  maxConsentDays: z.number().int().positive().optional(),
})

/**
 * Kick off a bank link flow. Calls Enable Banking POST /auth, then redirects
 * the user's browser to the bank's SCA page. The bank will redirect back to
 * `/api/banking/callback` with `?code=...&state=...` once consent is granted.
 *
 * NOTE: this server action calls `redirect()`, which throws a special
 * NEXT_REDIRECT error that Next.js uses for control flow. The form submitter
 * should NOT try/catch around this call.
 */
export async function startBankConnection(formData: FormData): Promise<void> {
  const parsed = startSchema.safeParse({
    aspspName: formData.get('aspspName'),
    aspspCountry: formData.get('aspspCountry'),
    maxConsentDays: formData.get('maxConsentDays')
      ? Number(formData.get('maxConsentDays'))
      : undefined,
  })
  if (!parsed.success) {
    throw new Error(parsed.error.issues.map((i) => i.message).join(', '))
  }
  if (!isEnableBankingConfigured()) {
    throw new Error('Enable Banking is not configured.')
  }
  const { aspspName, aspspCountry, maxConsentDays } = parsed.data
  const state = encodeAuthState({ aspspName, aspspCountry })
  // We omit `access.accounts` so Enable Banking presents the bank's full
  // account selector during SCA — the user picks what Florin should see.
  // We also omit `auth_method`: each bank names its own methods (e.g.
  // 'REDIRECT', 'DECOUPLED') and EB uses the primary one when we don't pick.
  const { url } = await startAuth({
    access: {
      valid_until: consentValidUntil(maxConsentDays),
      balances: true,
      transactions: true,
    },
    aspsp: { name: aspspName, country: aspspCountry },
    state,
    redirect_url: env.ENABLE_BANKING_REDIRECT_URL,
    psu_type: 'personal',
    language: 'fr',
  })
  // The bank's SCA URL is external, so we bypass Next.js typed routes here.
  redirect(url as never)
}

/**
 * Called from /api/banking/callback after the bank redirects back. Exchanges
 * the auth code for a session, persists a bank_connections row, and triggers
 * an initial sync. Returns the new connection id (or an error string).
 */
export async function completeBankConnection(input: {
  code: string
  aspspName: string
  aspspCountry: string
}): Promise<ActionResult<{ connectionId: string }>> {
  if (!isEnableBankingConfigured()) {
    return { success: false, error: 'Enable Banking is not configured.' }
  }
  try {
    const session = await createSession(input.code)
    const [row] = await db
      .insert(bankConnections)
      .values({
        provider: 'enable_banking',
        sessionId: session.session_id,
        aspspName: input.aspspName,
        aspspCountry: input.aspspCountry,
        status: 'active',
        validUntil: new Date(session.access.valid_until),
        // Default the watermark to today so new connections don't pull any
        // history and can't duplicate pre-existing legacy/manual data. Users
        // who actually want back-history can move the date earlier from the
        // connection's edit UI.
        syncStartDate: new Date(),
      })
      .returning({ id: bankConnections.id })
    if (!row) {
      return { success: false, error: 'Failed to persist bank connection' }
    }
    // Fire-and-await the initial sync inline so the user lands on /accounts
    // with their data already populated. The flow takes a few seconds but the
    // bank's SCA page already feels slow, so a few extra seconds at the end
    // are tolerable.
    await runSync(row.id)
    revalidatePath('/accounts')
    revalidatePath('/')
    return { success: true, data: { connectionId: row.id } }
  } catch (error: unknown) {
    return { success: false, error: extractErrorMessage(error) }
  }
}

/**
 * Trigger a sync across every active bank connection in one click. Bound to
 * the "Sync now" button on the dashboard header so the user can pull fresh
 * transactions without having to navigate to the Accounts page.
 */
export async function syncAllBanks(): Promise<
  ActionResult<{
    connectionsSynced: number
    accountsSynced: number
    transactionsInserted: number
  }>
> {
  try {
    const result = await syncAllConnections()
    revalidatePath('/')
    revalidatePath('/accounts')
    revalidatePath('/transactions')
    revalidatePath('/review')
    return {
      success: result.errors.length === 0,
      data: {
        connectionsSynced: result.connectionsSynced,
        accountsSynced: result.accountsSynced,
        transactionsInserted: result.transactionsInserted,
      },
      error: result.errors.length > 0 ? result.errors.map((e) => e.message).join('; ') : undefined,
    }
  } catch (error: unknown) {
    return { success: false, error: extractErrorMessage(error) }
  }
}

/** Manually trigger a re-sync for one connection. Returns counts. */
export async function syncBankConnection(
  connectionId: string,
): Promise<ActionResult<{ accountsSynced: number; transactionsInserted: number }>> {
  const parsed = z.uuid().safeParse(connectionId)
  if (!parsed.success) {
    return { success: false, error: 'Invalid connection id' }
  }
  try {
    const result = await runSync(connectionId)
    revalidatePath('/accounts')
    revalidatePath('/')
    return {
      success: result.errors.length === 0,
      data: {
        accountsSynced: result.accountsSynced,
        transactionsInserted: result.transactionsInserted,
      },
      error: result.errors.length > 0 ? result.errors.map((e) => e.message).join('; ') : undefined,
    }
  } catch (error: unknown) {
    return { success: false, error: extractErrorMessage(error) }
  }
}

/**
 * Nuke all Enable Banking transactions for this connection and reset the
 * sync watermark to today. Use this to recover from a bad overlap with
 * legacy XLSX data — the legacy rows stay untouched, the bank API rows
 * disappear, and the next sync starts fresh from today.
 *
 * Linked accounts keep their current balance (the bank API still knows the
 * true number) so net worth stays accurate.
 */
export async function resetBankConnectionSync(connectionId: string): Promise<ActionResult> {
  const parsed = z.uuid().safeParse(connectionId)
  if (!parsed.success) {
    return { success: false, error: 'Invalid connection id' }
  }
  try {
    const connection = await db.query.bankConnections.findFirst({
      where: eq(bankConnections.id, connectionId),
    })
    if (!connection) {
      return { success: false, error: 'Connection not found' }
    }
    const linkedAccounts = await db
      .select({ id: accounts.id })
      .from(accounts)
      .where(eq(accounts.bankConnectionId, connectionId))
    if (linkedAccounts.length > 0) {
      const accountIds = linkedAccounts.map((a) => a.id)
      await db
        .delete(transactions)
        .where(
          and(
            eq(transactions.source, 'enable_banking'),
            inArray(transactions.accountId, accountIds),
          ),
        )
    }
    await db
      .update(bankConnections)
      .set({
        syncStartDate: new Date(),
        lastSyncError: null,
        updatedAt: new Date(),
      })
      .where(eq(bankConnections.id, connectionId))
    revalidatePath('/accounts')
    revalidatePath('/')
    revalidatePath('/transactions')
    return { success: true }
  } catch (error: unknown) {
    return { success: false, error: extractErrorMessage(error) }
  }
}

/**
 * Disconnect a bank connection. Best-effort revoke at Enable Banking, then
 * delete the row. Linked accounts have their `bankConnectionId` nulled by the
 * `ON DELETE SET NULL` FK and stay around as historical data.
 */
export async function revokeBankConnection(connectionId: string): Promise<ActionResult> {
  const parsed = z.uuid().safeParse(connectionId)
  if (!parsed.success) {
    return { success: false, error: 'Invalid connection id' }
  }
  try {
    const connection = await db.query.bankConnections.findFirst({
      where: eq(bankConnections.id, connectionId),
    })
    if (!connection) {
      return { success: false, error: 'Connection not found' }
    }
    try {
      await deleteSession(connection.sessionId)
    } catch {
      // Best-effort — Enable Banking may have already invalidated the session.
    }
    // Demote the previously-linked accounts to manual so the user can keep
    // editing them by hand without seeing stale "synced" labels.
    await db
      .update(accounts)
      .set({
        syncProvider: 'manual',
        syncExternalId: null,
        bankConnectionId: null,
        updatedAt: new Date(),
      })
      .where(eq(accounts.bankConnectionId, connectionId))
    await db.delete(bankConnections).where(eq(bankConnections.id, connectionId))
    revalidatePath('/accounts')
    revalidatePath('/')
    return { success: true }
  } catch (error: unknown) {
    return { success: false, error: extractErrorMessage(error) }
  }
}

function extractErrorMessage(error: unknown): string {
  if (error instanceof EnableBankingError) {
    return `Enable Banking ${error.status ?? ''}: ${error.message}`
  }
  if (error instanceof Error) return error.message
  return 'Unknown error'
}
