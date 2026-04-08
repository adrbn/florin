/**
 * Enable Banking redirect callback.
 *
 * The bank's SCA page redirects the user back here with `?code=...&state=...`
 * once they've granted consent. We:
 *   1. Verify the HMAC-signed state to recover which ASPSP they were linking
 *   2. Exchange the code for a long-lived session via Enable Banking
 *   3. Persist a bank_connections row + run the initial sync
 *   4. Redirect to /accounts with a status query param so the UI can render
 *      a success/error toast on the next render
 *
 * On error we still redirect (rather than render JSON) so the user always
 * lands somewhere they can act from.
 */
import { type NextRequest, NextResponse } from 'next/server'
import { completeBankConnection } from '@/server/actions/banking'
import { decodeAuthState } from '@/server/banking/state'
import { env } from '@/server/env'

export async function GET(request: NextRequest): Promise<NextResponse> {
  // Prefer the configured public base URL over `new URL(request.url).origin`.
  // Behind a reverse proxy (e.g. Tailscale Serve) Next.js sees its internal
  // bind address (0.0.0.0:3000) in request.url, so using it here sends the
  // user to a dead host after a successful bank link. APP_BASE_URL is the
  // canonical external origin and is always correct when set.
  const { searchParams } = new URL(request.url)
  const origin = env.APP_BASE_URL
  const code = searchParams.get('code')
  const state = searchParams.get('state')
  const error = searchParams.get('error')
  const errorDescription = searchParams.get('error_description')

  // Banks return ?error=... when the user cancels or auth fails. We surface
  // it verbatim so the user knows whether they hit "Cancel" themselves or
  // whether the bank rejected the request.
  if (error) {
    const reason = encodeURIComponent(errorDescription ?? error)
    return NextResponse.redirect(`${origin}/accounts?bank_link=cancelled&reason=${reason}`)
  }

  if (!code || !state) {
    return NextResponse.redirect(`${origin}/accounts?bank_link=error&reason=missing_params`)
  }

  let aspspName: string
  let aspspCountry: string
  try {
    const decoded = decodeAuthState(state)
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
