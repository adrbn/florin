/**
 * Stateless HMAC-signed state for the Enable Banking OAuth-style flow.
 *
 * Why stateless: a self-hosted single-user app shouldn't pay the cost of a
 * dedicated `bank_auth_states` table just to remember "user X started linking
 * bank Y at time Z" for the 60 seconds between clicking Connect and getting
 * redirected back. We encode the pending auth into the `state` query param
 * itself, signed with a secret so the callback can trust it.
 *
 * Format: base64url(JSON({ n: nonce, a: aspspName, c: aspspCountry, t: ts })).<hmac>
 *
 * The HMAC covers the JSON payload exactly as transmitted, so any tampering
 * (replacing aspspName, replaying with a different timestamp) invalidates it.
 * We also reject states older than STATE_TTL_MS.
 *
 * This module is DB-agnostic — it takes the HMAC secret as a parameter instead
 * of reading from environment variables. Each app (web, desktop) supplies the
 * secret from its own source.
 */
import { createHmac, randomBytes, timingSafeEqual } from 'node:crypto'

const STATE_TTL_MS = 15 * 60 * 1000 // 15 minutes — enough for slow SCA flows

interface StatePayload {
  /** Random nonce — defends against replay if anything else was bypassed. */
  n: string
  /** ASPSP name — e.g. "La Banque Postale". */
  a: string
  /** ISO country — e.g. "FR". */
  c: string
  /** Created at (unix ms). */
  t: number
}

function base64UrlEncode(input: string): string {
  return Buffer.from(input, 'utf8')
    .toString('base64')
    .replace(/=+$/, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
}

function base64UrlDecode(input: string): string {
  const padded = input.replace(/-/g, '+').replace(/_/g, '/')
  return Buffer.from(padded, 'base64').toString('utf8')
}

function sign(payload: string, secret: string): string {
  const hmac = createHmac('sha256', secret)
  hmac.update(payload)
  return hmac.digest('base64').replace(/=+$/, '').replace(/\+/g, '-').replace(/\//g, '_')
}

export function encodeAuthState(
  secret: string,
  input: { aspspName: string; aspspCountry: string },
): string {
  const payload: StatePayload = {
    n: randomBytes(12).toString('hex'),
    a: input.aspspName,
    c: input.aspspCountry,
    t: Date.now(),
  }
  const encoded = base64UrlEncode(JSON.stringify(payload))
  const signature = sign(encoded, secret)
  return `${encoded}.${signature}`
}

export interface DecodedAuthState {
  aspspName: string
  aspspCountry: string
}

export function decodeAuthState(secret: string, state: string): DecodedAuthState {
  const dotIdx = state.indexOf('.')
  if (dotIdx <= 0 || dotIdx === state.length - 1) {
    throw new Error('Malformed bank auth state')
  }
  const payload = state.slice(0, dotIdx)
  const signature = state.slice(dotIdx + 1)
  const expected = sign(payload, secret)
  const expectedBuf = Buffer.from(expected, 'utf8')
  const actualBuf = Buffer.from(signature, 'utf8')
  if (expectedBuf.length !== actualBuf.length || !timingSafeEqual(expectedBuf, actualBuf)) {
    throw new Error('Bank auth state signature mismatch')
  }
  const parsed = JSON.parse(base64UrlDecode(payload)) as StatePayload
  if (Date.now() - parsed.t > STATE_TTL_MS) {
    throw new Error('Bank auth state expired')
  }
  return { aspspName: parsed.a, aspspCountry: parsed.c }
}
