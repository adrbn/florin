/**
 * Stateless HMAC-signed state for the Enable Banking OAuth-style flow — web
 * app adapter.
 *
 * Delegates to the pure implementation in @florin/core/banking, injecting the
 * signing secret from the NEXTAUTH_SECRET environment variable.
 */
import { env } from '@/server/env'
import {
  encodeAuthState as coreEncode,
  decodeAuthState as coreDecode,
} from '@florin/core/banking'
import type { DecodedAuthState } from '@florin/core/banking'

export type { DecodedAuthState }

export function encodeAuthState(input: { aspspName: string; aspspCountry: string }): string {
  return coreEncode(env.NEXTAUTH_SECRET, input)
}

export function decodeAuthState(state: string): DecodedAuthState {
  return coreDecode(env.NEXTAUTH_SECRET, state)
}
