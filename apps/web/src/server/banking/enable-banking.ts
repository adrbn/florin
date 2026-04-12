/**
 * Enable Banking API client — web app adapter.
 *
 * Delegates to the DB-agnostic client in @florin/core/banking, injecting the
 * config from environment variables.
 */
import { env } from '@/server/env'
import type { EnableBankingConfig } from '@florin/core/banking'
import {
  EnableBankingError,
  listAspsps as coreListAspsps,
  startAuth as coreStartAuth,
  createSession as coreCreateSession,
  getSession as coreGetSession,
  deleteSession as coreDeleteSession,
  getAccountDetails as coreGetAccountDetails,
  getBalances as coreGetBalances,
  getTransactions as coreGetTransactions,
} from '@florin/core/banking'
import type {
  AspspListResponse,
  StartAuthRequest,
  StartAuthResponse,
  CreateSessionResponse,
  Session,
  AccountDetails,
  BalancesResponse,
  TransactionsResponse,
} from '@florin/core/banking'

// Re-export types and error so existing consumers don't need to change imports.
export { EnableBankingError }
export type {
  AspspListResponse,
  StartAuthRequest,
  StartAuthResponse,
  CreateSessionResponse,
  Session,
  AccountDetails,
  BalancesResponse,
  TransactionsResponse,
}

function getConfig(): EnableBankingConfig {
  const appId = env.ENABLE_BANKING_APP_ID
  const privateKeyPath = env.ENABLE_BANKING_PRIVATE_KEY_PATH
  if (!appId || !privateKeyPath) {
    throw new EnableBankingError(
      'Enable Banking is not configured. Set ENABLE_BANKING_APP_ID and ENABLE_BANKING_PRIVATE_KEY_PATH in .env, then restart the dev server.',
    )
  }
  return { appId, privateKeyPath }
}

export function isEnableBankingConfigured(): boolean {
  return Boolean(env.ENABLE_BANKING_APP_ID && env.ENABLE_BANKING_PRIVATE_KEY_PATH)
}

export async function listAspsps(country: string): Promise<AspspListResponse> {
  return coreListAspsps(getConfig(), country)
}

export async function startAuth(input: StartAuthRequest): Promise<StartAuthResponse> {
  return coreStartAuth(getConfig(), input)
}

export async function createSession(code: string): Promise<CreateSessionResponse> {
  return coreCreateSession(getConfig(), code)
}

export async function getSession(sessionId: string): Promise<Session> {
  return coreGetSession(getConfig(), sessionId)
}

export async function deleteSession(sessionId: string): Promise<void> {
  await coreDeleteSession(getConfig(), sessionId)
}

export async function getAccountDetails(accountUid: string): Promise<AccountDetails> {
  return coreGetAccountDetails(getConfig(), accountUid)
}

export async function getBalances(accountUid: string): Promise<BalancesResponse> {
  return coreGetBalances(getConfig(), accountUid)
}

export async function getTransactions(
  accountUid: string,
  params: { dateFrom: string; dateTo: string; continuationKey?: string },
): Promise<TransactionsResponse> {
  return coreGetTransactions(getConfig(), accountUid, params)
}
