import { compare } from 'bcryptjs'
import NextAuth from 'next-auth'
import Credentials from 'next-auth/providers/credentials'
import { z } from 'zod'
import { authConfig } from '@/server/auth.config'
import { env } from '@/server/env'

const credentialsSchema = z.object({
  email: z.email(),
  password: z.string().min(1),
})

export const { handlers, auth, signIn, signOut } = NextAuth({
  ...authConfig,
  secret: env.NEXTAUTH_SECRET,
  providers: [
    Credentials({
      name: 'Credentials',
      credentials: {
        email: { label: 'Email', type: 'email' },
        password: { label: 'Password', type: 'password' },
      },
      async authorize(credentials) {
        const parsed = credentialsSchema.safeParse(credentials)
        if (!parsed.success) {
          return null
        }

        const { email, password } = parsed.data

        const adminEmail = env.ADMIN_EMAIL
        const adminPasswordHash = env.ADMIN_PASSWORD_HASH

        if (!adminEmail || !adminPasswordHash) {
          return null
        }

        if (email.toLowerCase() !== adminEmail.toLowerCase()) {
          return null
        }

        const valid = await compare(password, adminPasswordHash)
        if (!valid) {
          return null
        }

        return {
          id: 'admin',
          email: adminEmail,
          name: 'Admin',
        }
      },
    }),
  ],
})
