import type { NextAuthConfig } from 'next-auth'

/**
 * Edge-safe Auth.js config — no Node-only deps (bcryptjs, db, etc).
 *
 * This is the slice of the auth config that the middleware can import.
 * The full config in `./auth.ts` extends this with the Credentials provider
 * (which uses bcryptjs and is therefore Node-runtime only).
 */
export const authConfig = {
  trustHost: true,
  session: {
    strategy: 'jwt',
    maxAge: 60 * 60 * 24 * 30, // 30 days
  },
  pages: {
    signIn: '/login',
  },
  providers: [],
  callbacks: {
    authorized({ auth, request }) {
      const { pathname } = request.nextUrl

      // Public endpoints — always allow
      if (pathname.startsWith('/api/auth') || pathname === '/api/health') {
        return true
      }

      // Public pages
      if (pathname === '/login') {
        return true
      }

      return Boolean(auth?.user)
    },
  },
} satisfies NextAuthConfig
