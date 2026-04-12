/**
 * Enable Banking API client.
 *
 * Enable Banking is a PSD2 aggregator that lets us read EU bank accounts via a
 * single REST API. We use it in their free "restricted mode" — you can connect
 * any account that the registered application owner controls, no business
 * activation required. Docs: https://enablebanking.com/docs/api/reference
 *
 * Auth model: every request carries a short-lived JWT signed with RS256 using
 * the app's RSA private key (downloaded once at app registration). The JWT
 * itself encodes the app id in `kid`, has a 1h lifetime, and we cache it on
 * the module so successive requests in the same process re-use it until it
 * gets close to expiry.
 *
 * Why no `jsonwebtoken` dependency: node:crypto can produce RS256 signatures
 * directly with `createSign`. One less package to audit + smaller cold start.
 *
 * This module is DB-agnostic — it takes an {@link EnableBankingConfig} as a
 * parameter instead of reading from environment variables. Each app (web,
 * desktop) supplies the config from its own source (env vars, SQLite settings).
 */
import { createSign } from 'node:crypto'
import { readFile } from 'node:fs/promises'
import type {
  AccountDetails,
  AspspListResponse,
  BalancesResponse,
  CreateSessionResponse,
  Session,
  StartAuthRequest,
  StartAuthResponse,
  TransactionsResponse,
} from './types'

/** Configuration required to authenticate with the Enable Banking API. */
export interface EnableBankingConfig {
  /** Application id (kid) registered with Enable Banking. */
  appId: string
  /** Absolute path to the RSA private key PEM file. */
  privateKeyPath: string
}

const API_BASE = 'https://api.enablebanking.com'
/** JWT lifetime — Enable Banking accepts up to 1 hour. We use 50 minutes so a
 * cached token never expires mid-request. */
const JWT_LIFETIME_SEC = 50 * 60

interface CachedJwt {
  token: string
  /** Unix epoch (seconds) at which the token stops being safely usable. */
  expiresAt: number
}

let jwtCache: CachedJwt | null = null
let cachedPrivateKey: string | null = null

export class EnableBankingError extends Error {
  constructor(
    message: string,
    public readonly status?: number,
    public readonly body?: unknown,
  ) {
    super(message)
    this.name = 'EnableBankingError'
  }
}

async function loadPrivateKey(config: EnableBankingConfig): Promise<string> {
  if (cachedPrivateKey) return cachedPrivateKey
  try {
    const pem = await readFile(config.privateKeyPath, 'utf8')
    cachedPrivateKey = pem
    return pem
  } catch (error: unknown) {
    const reason = error instanceof Error ? error.message : 'unknown error'
    throw new EnableBankingError(
      `Cannot read Enable Banking private key at ${config.privateKeyPath}: ${reason}`,
    )
  }
}

function base64UrlEncode(input: Buffer | string): string {
  const buf = typeof input === 'string' ? Buffer.from(input, 'utf8') : input
  return buf.toString('base64').replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_')
}

async function signJwt(config: EnableBankingConfig): Promise<string> {
  const privateKey = await loadPrivateKey(config)
  const now = Math.floor(Date.now() / 1000)
  const header = { typ: 'JWT', alg: 'RS256', kid: config.appId }
  const payload = {
    iss: 'enablebanking.com',
    aud: 'api.enablebanking.com',
    iat: now,
    exp: now + JWT_LIFETIME_SEC,
  }
  const headerB64 = base64UrlEncode(JSON.stringify(header))
  const payloadB64 = base64UrlEncode(JSON.stringify(payload))
  const signingInput = `${headerB64}.${payloadB64}`
  const signer = createSign('RSA-SHA256')
  signer.update(signingInput)
  signer.end()
  const signature = signer.sign(privateKey)
  const sigB64 = base64UrlEncode(signature)
  return `${signingInput}.${sigB64}`
}

async function getJwt(config: EnableBankingConfig): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  // Refresh 5 minutes before actual expiry to absorb clock skew.
  if (jwtCache && jwtCache.expiresAt - 300 > now) {
    return jwtCache.token
  }
  const token = await signJwt(config)
  jwtCache = { token, expiresAt: now + JWT_LIFETIME_SEC }
  return token
}

interface RequestOptions {
  method?: 'GET' | 'POST' | 'DELETE'
  query?: Record<string, string | number | undefined>
  body?: unknown
}

async function request<T>(
  config: EnableBankingConfig,
  path: string,
  opts: RequestOptions = {},
): Promise<T> {
  const jwt = await getJwt(config)
  const url = new URL(`${API_BASE}${path}`)
  if (opts.query) {
    for (const [key, value] of Object.entries(opts.query)) {
      if (value !== undefined) url.searchParams.set(key, String(value))
    }
  }
  const response = await fetch(url.toString(), {
    method: opts.method ?? 'GET',
    headers: {
      Authorization: `Bearer ${jwt}`,
      'Content-Type': 'application/json',
      Accept: 'application/json',
    },
    body: opts.body !== undefined ? JSON.stringify(opts.body) : undefined,
    cache: 'no-store',
  })
  const text = await response.text()
  let parsed: unknown
  try {
    parsed = text ? JSON.parse(text) : null
  } catch {
    parsed = text
  }
  if (!response.ok) {
    const bodyStr = typeof parsed === 'string' ? parsed : JSON.stringify(parsed)
    throw new EnableBankingError(
      `Enable Banking API ${response.status} on ${opts.method ?? 'GET'} ${path} — ${bodyStr}`,
      response.status,
      parsed,
    )
  }
  return parsed as T
}

// ============ Public API ============

/** List banks (ASPSPs) Enable Banking can connect to. Filter by country to keep
 * the response small — France alone returns ~30 entries. */
export async function listAspsps(
  config: EnableBankingConfig,
  country: string,
): Promise<AspspListResponse> {
  return request<AspspListResponse>(config, '/aspsps', { query: { country } })
}

/** Start a consent flow. Returns a URL to redirect the user to (the bank's own
 * SCA page). After they authenticate, the bank redirects to `redirect_url`
 * with `?code=...&state=...` query params. */
export async function startAuth(
  config: EnableBankingConfig,
  input: StartAuthRequest,
): Promise<StartAuthResponse> {
  return request<StartAuthResponse>(config, '/auth', { method: 'POST', body: input })
}

/** Exchange the auth code from the callback for a long-lived session. */
export async function createSession(
  config: EnableBankingConfig,
  code: string,
): Promise<CreateSessionResponse> {
  return request<CreateSessionResponse>(config, '/sessions', { method: 'POST', body: { code } })
}

/** Fetch a session including the linked account UIDs and metadata. */
export async function getSession(
  config: EnableBankingConfig,
  sessionId: string,
): Promise<Session> {
  return request<Session>(config, `/sessions/${encodeURIComponent(sessionId)}`)
}

/** Revoke a session (best-effort — Enable Banking may already have closed it
 * if validUntil has passed). */
export async function deleteSession(
  config: EnableBankingConfig,
  sessionId: string,
): Promise<void> {
  await request<void>(config, `/sessions/${encodeURIComponent(sessionId)}`, { method: 'DELETE' })
}

/** Get full account metadata (name, IBAN, currency, etc.) for one UID. */
export async function getAccountDetails(
  config: EnableBankingConfig,
  accountUid: string,
): Promise<AccountDetails> {
  return request<AccountDetails>(config, `/accounts/${encodeURIComponent(accountUid)}/details`)
}

/** Get current balances for one account UID. */
export async function getBalances(
  config: EnableBankingConfig,
  accountUid: string,
): Promise<BalancesResponse> {
  return request<BalancesResponse>(config, `/accounts/${encodeURIComponent(accountUid)}/balances`)
}

/** Get transactions in a date range. Enable Banking returns at most a few
 * hundred per page — caller should loop on `continuation_key` until null. */
export async function getTransactions(
  config: EnableBankingConfig,
  accountUid: string,
  params: { dateFrom: string; dateTo: string; continuationKey?: string },
): Promise<TransactionsResponse> {
  return request<TransactionsResponse>(
    config,
    `/accounts/${encodeURIComponent(accountUid)}/transactions`,
    {
      query: {
        date_from: params.dateFrom,
        date_to: params.dateTo,
        continuation_key: params.continuationKey,
      },
    },
  )
}
