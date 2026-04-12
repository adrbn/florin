import { NextResponse } from 'next/server'
import type { NextRequest } from 'next/server'

const PIN_COOKIE = 'florin-pin-ok'
const PIN_ENABLED_COOKIE = 'florin-pin-enabled'

/**
 * Paths that are always accessible regardless of PIN state.
 */
const PUBLIC_PREFIXES = ['/pin', '/_next/', '/favicon']

function isPublic(pathname: string): boolean {
  return PUBLIC_PREFIXES.some((prefix) => pathname.startsWith(prefix))
}

/**
 * Middleware: if PIN protection is active (signalled by the `florin-pin-enabled`
 * cookie set by the settings page), redirect unauthenticated requests to /pin.
 *
 * Why a cookie instead of a direct SQLite read?
 * Next.js middleware runs in the Edge runtime which cannot use Node.js native
 * modules (better-sqlite3). The Settings page calls `syncPinEnabledCookie()`
 * (a server action) after any PIN change so the middleware always has an
 * up-to-date signal without touching the database.
 */
export function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl

  if (isPublic(pathname)) {
    return NextResponse.next()
  }

  const pinEnabled = request.cookies.get(PIN_ENABLED_COOKIE)?.value === '1'
  if (!pinEnabled) {
    return NextResponse.next()
  }

  const authed = request.cookies.get(PIN_COOKIE)?.value === '1'
  if (authed) {
    return NextResponse.next()
  }

  const loginUrl = request.nextUrl.clone()
  loginUrl.pathname = '/pin'
  return NextResponse.redirect(loginUrl)
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico).*)'],
}
