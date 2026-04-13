/**
 * Enable Banking redirect callback — desktop version.
 *
 * The bank's SCA page was opened in the system browser. After the user
 * authenticates, the bank redirects back to http://127.0.0.1:<port>/api/banking/callback
 * with ?code=...&state=... query params. We:
 *   1. Decode and verify the HMAC-signed state
 *   2. Exchange the code for a session via Enable Banking
 *   3. Persist the bank_connections row and run the initial sync
 *   4. Redirect the browser to /accounts with a status banner
 */
import { type NextRequest, NextResponse } from 'next/server'
import { decodeAuthState } from '@florin/core/banking'
import { completeBankConnection } from '@/server/actions/banking'
import { getAuthStateSecret } from '@/server/banking/config'

export const dynamic = 'force-dynamic'

export async function GET(request: NextRequest): Promise<NextResponse> {
  const { searchParams, origin } = new URL(request.url)
  const code = searchParams.get('code')
  const state = searchParams.get('state')
  const error = searchParams.get('error')
  const errorDescription = searchParams.get('error_description')

  if (error) {
    const reason = encodeURIComponent(errorDescription ?? error)
    return NextResponse.redirect(`${origin}/accounts?bank_link=cancelled&reason=${reason}`)
  }

  if (!code || !state) {
    return NextResponse.redirect(`${origin}/accounts?bank_link=error&reason=missing_params`)
  }

  const secret = await getAuthStateSecret()
  if (!secret) {
    return NextResponse.redirect(`${origin}/accounts?bank_link=error&reason=no_auth_secret`)
  }

  let aspspName: string
  let aspspCountry: string
  try {
    const decoded = decodeAuthState(secret, state)
    aspspName = decoded.aspspName
    aspspCountry = decoded.aspspCountry
  } catch (e: unknown) {
    const reason = e instanceof Error ? encodeURIComponent(e.message) : 'invalid_state'
    return NextResponse.redirect(`${origin}/accounts?bank_link=error&reason=${reason}`)
  }

  const result = await completeBankConnection({ code, aspspName, aspspCountry })
  if (!result.success) {
    const reason = encodeURIComponent(result.error ?? 'unknown')
    return NextResponse.redirect(`${origin}/accounts?bank_link=error&reason=${reason}`)
  }

  return NextResponse.redirect(
    `${origin}/accounts?bank_link=success&connection=${result.data?.connectionId ?? ''}`,
  )
}
