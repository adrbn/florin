#!/usr/bin/env tsx
/**
 * CLI helper to hash a password for ADMIN_PASSWORD_HASH.
 *
 * Usage: pnpm tsx scripts/hash-password.ts <password>
 *
 * Prints only the bcrypt hash to stdout — paste it into .env as
 * ADMIN_PASSWORD_HASH=<hash>
 */
import { hash } from 'bcryptjs'

const BCRYPT_ROUNDS = 12

async function main(): Promise<void> {
  const password = process.argv[2]

  if (!password) {
    process.stderr.write('Usage: pnpm tsx scripts/hash-password.ts <password>\n')
    process.exit(1)
  }

  const hashed = await hash(password, BCRYPT_ROUNDS)
  process.stdout.write(`${hashed}\n`)
}

main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : 'Unknown error'
  process.stderr.write(`Failed to hash password: ${message}\n`)
  process.exit(1)
})
