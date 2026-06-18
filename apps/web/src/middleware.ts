import NextAuth from 'next-auth'
import { NextResponse } from 'next/server'
import { authConfig } from '@/server/auth.config'

const { auth } = NextAuth(authConfig)

// Wrap NextAuth's middleware so we can expose the request pathname to server
// components via a custom header. The (dashboard) layout reads `x-pathname`
// to know whether it is already on /onboarding and avoid a redirect loop.
// The `auth()` wrapper still enforces the redirects declared in authConfig;
// when it lets the request through (returns void) we forward it with the
// extra header attached.
export const middleware = auth((req) => {
  const headers = new Headers(req.headers)
  headers.set('x-pathname', req.nextUrl.pathname)
  return NextResponse.next({ request: { headers } })
})

export const config = {
  matcher: [
    '/((?!_next/static|_next/image|favicon.ico|manifest.webmanifest|icon-.*\\.png|.*\\.svg$).*)',
  ],
}
