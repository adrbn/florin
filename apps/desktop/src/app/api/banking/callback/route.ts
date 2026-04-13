/**
 * Enable Banking redirect callback — desktop version.
 *
 * The bank's SCA page was opened in the system browser. After the user
 * authenticates, the bank redirects back to https://127.0.0.1:3847/api/banking/callback
 * with ?code=...&state=... query params. We:
 *   1. Decode and verify the HMAC-signed state
 *   2. Exchange the code for a session via Enable Banking
 *   3. Persist the bank_connections row and run the initial sync
 *   4. Return a simple HTML page telling the user to go back to Florin
 *
 * We don't redirect to /accounts because this runs in the system browser,
 * not inside Electron. Instead we return a static "done" page and the
 * Electron main process detects the navigation and refreshes the app.
 */
import { type NextRequest, NextResponse } from 'next/server'
import { decodeAuthState } from '@florin/core/banking'
import { completeBankConnection } from '@/server/actions/banking'
import { getAuthStateSecret } from '@/server/banking/config'

export const dynamic = 'force-dynamic'

function htmlResponse(title: string, message: string, isError: boolean): NextResponse {
  const color = isError ? '#ef4444' : '#10b981'
  const icon = isError ? '&#10007;' : '&#10003;'
  const html = `<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Florin — ${title}</title>
<style>
  body { margin:0; min-height:100vh; display:flex; align-items:center; justify-content:center;
         font-family:-apple-system,system-ui,sans-serif; background:#0f1117; color:#e5e7eb; }
  .card { text-align:center; max-width:400px; padding:3rem 2rem; }
  .icon { font-size:3rem; color:${color}; margin-bottom:1rem; }
  h1 { font-size:1.25rem; font-weight:600; margin:0 0 0.75rem; }
  p { font-size:0.875rem; color:#9ca3af; margin:0; line-height:1.5; }
</style></head>
<body><div class="card">
  <div class="icon">${icon}</div>
  <h1>${title}</h1>
  <p>${message}</p>
</div></body></html>`
  return new NextResponse(html, {
    headers: { 'Content-Type': 'text/html; charset=utf-8' },
  })
}

export async function GET(request: NextRequest): Promise<NextResponse> {
  const { searchParams } = new URL(request.url)
  const code = searchParams.get('code')
  const state = searchParams.get('state')
  const error = searchParams.get('error')
  const errorDescription = searchParams.get('error_description')

  if (error) {
    return htmlResponse(
      'Bank linking cancelled',
      errorDescription ?? error,
      true,
    )
  }

  if (!code || !state) {
    return htmlResponse('Missing parameters', 'The callback URL is missing required parameters.', true)
  }

  const secret = await getAuthStateSecret()
  if (!secret) {
    return htmlResponse('Configuration error', 'Auth state secret is not configured.', true)
  }

  let aspspName: string
  let aspspCountry: string
  try {
    const decoded = decodeAuthState(secret, state)
    aspspName = decoded.aspspName
    aspspCountry = decoded.aspspCountry
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : 'Invalid state token'
    return htmlResponse('Invalid callback', msg, true)
  }

  const result = await completeBankConnection({ code, aspspName, aspspCountry })
  if (!result.success) {
    return htmlResponse('Connection failed', result.error ?? 'Unknown error', true)
  }

  return htmlResponse(
    'Bank connected',
    `${aspspName} is now linked to Florin. You can close this tab and return to the app — your accounts will appear momentarily.`,
    false,
  )
}
