'use server'

import { cookies } from 'next/headers'
import { verifyPin } from '@/server/actions/pin'

const COOKIE_NAME = 'florin-pin-ok'
const COOKIE_MAX_AGE = 60 * 60 * 24 // 24 hours in seconds

/**
 * Verify the PIN and, on success, set the session cookie.
 * Returns true if the PIN was correct, false otherwise.
 */
export async function verifyPinAndSetCookie(pin: string): Promise<boolean> {
  const ok = await verifyPin(pin)
  if (ok) {
    const cookieStore = await cookies()
    cookieStore.set(COOKIE_NAME, '1', {
      httpOnly: true,
      sameSite: 'strict',
      maxAge: COOKIE_MAX_AGE,
      path: '/',
    })
  }
  return ok
}
