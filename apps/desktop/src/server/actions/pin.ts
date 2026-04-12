'use server'

import { promisify } from 'node:util'
import crypto from 'node:crypto'
import { eq } from 'drizzle-orm'
import { cookies } from 'next/headers'
import { db } from '@/db/client'
import { settings } from '@/db/schema'

const PIN_ENABLED_COOKIE = 'florin-pin-enabled'

const scryptAsync = promisify(crypto.scrypt)

const SALT_BYTES = 16
const KEY_LEN = 64

/**
 * Hash a PIN using scrypt. Returns a string of the form `scrypt:<hex-salt>:<hex-hash>`.
 */
async function hashPin(pin: string): Promise<string> {
  const salt = crypto.randomBytes(SALT_BYTES).toString('hex')
  const hash = (await scryptAsync(pin, salt, KEY_LEN)) as Buffer
  return `scrypt:${salt}:${hash.toString('hex')}`
}

/**
 * Compare a plain PIN against a stored `scrypt:<salt>:<hash>` string.
 */
async function comparePin(pin: string, stored: string): Promise<boolean> {
  const parts = stored.split(':')
  if (parts.length !== 3 || parts[0] !== 'scrypt') return false
  const [, salt, expected] = parts
  const actual = (await scryptAsync(pin, salt, KEY_LEN)) as Buffer
  const expectedBuf = Buffer.from(expected, 'hex')
  // Constant-time comparison to prevent timing attacks
  if (actual.length !== expectedBuf.length) return false
  return crypto.timingSafeEqual(actual, expectedBuf)
}

/**
 * Read the stored pin_hash from the settings table.
 */
async function getPinHash(): Promise<string | null> {
  const row = await db
    .select({ value: settings.value })
    .from(settings)
    .where(eq(settings.key, 'pin_hash'))
    .limit(1)
  return row[0]?.value ?? null
}

/**
 * Verify a PIN against the stored hash. Returns true if the PIN matches.
 */
export async function verifyPin(pin: string): Promise<boolean> {
  const stored = await getPinHash()
  if (!stored) return false
  return comparePin(pin, stored)
}

/**
 * Set (or update) the PIN. Stores a scrypt hash in the settings table
 * and syncs the middleware cookie.
 */
export async function setPin(pin: string): Promise<void> {
  const hash = await hashPin(pin)
  await db
    .insert(settings)
    .values({ key: 'pin_hash', value: hash })
    .onConflictDoUpdate({ target: settings.key, set: { value: hash } })
  await syncPinEnabledCookie()
}

/**
 * Remove the PIN. Deletes the pin_hash row and clears the middleware cookie.
 */
export async function removePin(): Promise<void> {
  await db.delete(settings).where(eq(settings.key, 'pin_hash'))
  await syncPinEnabledCookie()
}

/**
 * Check whether a PIN has been configured.
 */
export async function isPinEnabled(): Promise<boolean> {
  const hash = await getPinHash()
  return hash !== null
}

/**
 * Sync the `florin-pin-enabled` cookie so the Edge middleware can know
 * whether PIN protection is active without touching SQLite.
 * Call this after setPin() and removePin().
 */
export async function syncPinEnabledCookie(): Promise<void> {
  const enabled = await isPinEnabled()
  const cookieStore = await cookies()
  if (enabled) {
    cookieStore.set(PIN_ENABLED_COOKIE, '1', {
      httpOnly: true,
      sameSite: 'strict',
      path: '/',
      // No maxAge — persists until the browser session or until removePin clears it.
    })
  } else {
    cookieStore.delete(PIN_ENABLED_COOKIE)
    // Also clear the auth cookie so an existing session is not left dangling.
    cookieStore.delete('florin-pin-ok')
  }
}
