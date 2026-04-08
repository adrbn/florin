import NextAuth from 'next-auth'
import { authConfig } from '@/server/auth.config'

export const { auth: middleware } = NextAuth(authConfig)

export const config = {
  matcher: [
    '/((?!_next/static|_next/image|favicon.ico|manifest.webmanifest|icon-.*\\.png|.*\\.svg$).*)',
  ],
}
