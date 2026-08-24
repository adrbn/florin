import { auth } from '@/server/auth'
import { env } from '@/server/env'

/**
 * Session or bearer token, for the routes the native client calls.
 *
 * A phone has no NextAuth cookie to present, so the v2 feed accepts a token as
 * well. The token is opt-in: leave `FLORIN_API_TOKEN` unset and every one of
 * these routes stays session-only, exactly as strict as the rest of the
 * deployment. Nothing here widens access to the browser surfaces.
 */
export async function authorizeApi(request: Request): Promise<boolean> {
  const session = await auth()
  if (session?.user) return true

  const expected = env.FLORIN_API_TOKEN
  if (!expected) return false
  const header = request.headers.get('authorization') ?? ''
  const presented = header.startsWith('Bearer ') ? header.slice(7) : ''
  // Compare the full length rather than bailing on the first differing byte,
  // so the timing doesn't leak how much of the token was guessed.
  if (presented.length !== expected.length) return false
  let diff = 0
  for (let i = 0; i < expected.length; i++) diff |= presented.charCodeAt(i) ^ expected.charCodeAt(i)
  return diff === 0
}
