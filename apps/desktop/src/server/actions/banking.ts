'use server'

import { and, eq, inArray } from 'drizzle-orm'
import { revalidatePath } from 'next/cache'
import { z } from 'zod'
import { db } from '@/db/client'
import { accounts, bankConnections, transactions } from '@/db/schema'
import {
  EnableBankingError,
  createSession,
  deleteSession,
  listAspsps as coreListAspsps,
  startAuth as coreStartAuth,
} from '@florin/core/banking'
import { encodeAuthState } from '@florin/core/banking'
import type { Aspsp } from '@florin/core/banking'
import { getEnableBankingConfig, getAuthStateSecret } from '@/server/banking/config'
import { syncConnection as runSync } from '@/server/banking/sync'
import { syncAllConnections } from '@/server/banking/sync-all'

export interface ActionResult<T = void> {
  success: boolean
  error?: string
  data?: T
}

function consentValidUntil(maxDays?: number): string {
  const days = Math.min(maxDays ?? 180, 180)
  return new Date(Date.now() + days * 24 * 60 * 60 * 1000).toISOString()
}

export async function isEnableBankingConfigured(): Promise<boolean> {
  const config = await getEnableBankingConfig()
  return config !== null
}

/** List banks for a given country (defaults to FR). */
export async function listBanks(country = 'FR'): Promise<ActionResult<ReadonlyArray<Aspsp>>> {
  const config = await getEnableBankingConfig()
  if (!config) {
    return { success: false, error: 'Enable Banking is not configured.' }
  }
  try {
    const { aspsps } = await coreListAspsps(config, country)
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
  redirectUrl: z.string().min(1),
})

/**
 * Kick off a bank link flow. Returns the bank's SCA URL for the desktop app
 * to open in the system browser.
 */
export async function startBankConnection(input: {
  aspspName: string
  aspspCountry: string
  maxConsentDays?: number
  redirectUrl: string
}): Promise<ActionResult<{ url: string }>> {
  const parsed = startSchema.safeParse(input)
  if (!parsed.success) {
    return { success: false, error: parsed.error.issues.map((i) => i.message).join(', ') }
  }
  const config = await getEnableBankingConfig()
  if (!config) {
    return { success: false, error: 'Enable Banking is not configured.' }
  }
  const secret = await getAuthStateSecret()
  if (!secret) {
    return { success: false, error: 'Auth state secret not configured.' }
  }
  try {
    const { aspspName, aspspCountry, maxConsentDays, redirectUrl } = parsed.data
    const state = encodeAuthState(secret, { aspspName, aspspCountry })
    const { url } = await coreStartAuth(config, {
      access: {
        valid_until: consentValidUntil(maxConsentDays),
        balances: true,
        transactions: true,
      },
      aspsp: { name: aspspName, country: aspspCountry },
      state,
      redirect_url: redirectUrl,
      psu_type: 'personal',
      language: 'fr',
    })
    return { success: true, data: { url } }
  } catch (error: unknown) {
    return { success: false, error: extractErrorMessage(error) }
  }
}

/**
 * Called after the bank redirects back. Exchanges the auth code for a session,
 * persists a bank_connections row, and triggers an initial sync.
 */
export async function completeBankConnection(input: {
  code: string
  aspspName: string
  aspspCountry: string
}): Promise<ActionResult<{ connectionId: string }>> {
  const config = await getEnableBankingConfig()
  if (!config) {
    return { success: false, error: 'Enable Banking is not configured.' }
  }
  try {
    const session = await createSession(config, input.code)
    const [row] = await db
      .insert(bankConnections)
      .values({
        provider: 'enable_banking',
        sessionId: session.session_id,
        aspspName: input.aspspName,
        aspspCountry: input.aspspCountry,
        status: 'active',
        validUntil: new Date(session.access.valid_until).toISOString(),
        syncStartDate: new Date().toISOString(),
      })
      .returning({ id: bankConnections.id })
    if (!row) {
      return { success: false, error: 'Failed to persist bank connection' }
    }
    await runSync(row.id)
    revalidatePath('/accounts')
    revalidatePath('/')
    return { success: true, data: { connectionId: row.id } }
  } catch (error: unknown) {
    return { success: false, error: extractErrorMessage(error) }
  }
}

/** Trigger a sync across every active bank connection. */
export async function syncAllBanks(): Promise<
  ActionResult<{
    connectionsSynced: number
    inactiveConnections: number
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
        inactiveConnections: result.inactiveConnections,
        accountsSynced: result.accountsSynced,
        transactionsInserted: result.transactionsInserted,
      },
      error: result.errors.length > 0 ? result.errors.map((e) => e.message).join('; ') : undefined,
    }
  } catch (error: unknown) {
    return { success: false, error: extractErrorMessage(error) }
  }
}

/** Manually trigger a re-sync for one connection. */
export async function syncBankConnection(
  connectionId: string,
): Promise<ActionResult<{ accountsSynced: number; transactionsInserted: number }>> {
  try {
    const result = await runSync(connectionId)
    revalidatePath('/accounts')
    revalidatePath('/')
    // Partial success: report success if at least some accounts synced,
    // even if some individual operations failed (e.g. transactions 422 on
    // an account type the bank doesn't fully support via PSD2).
    return {
      success: result.accountsSynced > 0,
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
 * sync watermark to today.
 */
export async function resetBankConnectionSync(connectionId: string): Promise<ActionResult> {
  try {
    const connection = await db
      .select()
      .from(bankConnections)
      .where(eq(bankConnections.id, connectionId))
      .get()
    if (!connection) {
      return { success: false, error: 'Connection not found' }
    }
    const linkedAccounts = await db
      .select({ id: accounts.id })
      .from(accounts)
      .where(eq(accounts.bankConnectionId, connectionId))
      .all()
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
        syncStartDate: new Date().toISOString(),
        lastSyncError: null,
        updatedAt: new Date().toISOString(),
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
 * delete the row. Linked accounts have their bankConnectionId nulled by the
 * ON DELETE SET NULL FK.
 */
export async function revokeBankConnection(
  connectionId: string,
  opts?: { deleteTransactions?: boolean },
): Promise<ActionResult> {
  try {
    const connection = await db
      .select()
      .from(bankConnections)
      .where(eq(bankConnections.id, connectionId))
      .get()
    if (!connection) {
      return { success: false, error: 'Connection not found' }
    }
    const config = await getEnableBankingConfig()
    if (config) {
      try {
        await deleteSession(config, connection.sessionId)
      } catch {
        // Best-effort — Enable Banking may have already invalidated the session.
      }
    }

    const linkedAccounts = await db
      .select({ id: accounts.id })
      .from(accounts)
      .where(eq(accounts.bankConnectionId, connectionId))
      .all()

    // Optionally delete all bank-synced transactions for linked accounts
    if (opts?.deleteTransactions && linkedAccounts.length > 0) {
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
      .update(accounts)
      .set({
        syncProvider: 'manual',
        syncExternalId: null,
        bankConnectionId: null,
        updatedAt: new Date().toISOString(),
      })
      .where(eq(accounts.bankConnectionId, connectionId))
    await db.delete(bankConnections).where(eq(bankConnections.id, connectionId))
    revalidatePath('/accounts')
    revalidatePath('/')
    revalidatePath('/transactions')
    return { success: true }
  } catch (error: unknown) {
    return { success: false, error: extractErrorMessage(error) }
  }
}

function extractErrorMessage(error: unknown): string {
  if (error instanceof EnableBankingError) {
    // Extract a short reason from the API response body if possible,
    // otherwise truncate the verbose message to something readable.
    const body = error.body as Record<string, unknown> | undefined
    if (body && typeof body === 'object') {
      if (typeof body.message === 'string') return body.message
      if (typeof body.error === 'string') return body.error
    }
    return `Enable Banking error ${error.status ?? ''}`
  }
  if (error instanceof Error) {
    return error.message.length > 120 ? `${error.message.slice(0, 120)}…` : error.message
  }
  return 'Unknown error'
}
