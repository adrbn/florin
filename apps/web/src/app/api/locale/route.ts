import { NextResponse } from 'next/server'
import { cookies } from 'next/headers'
import { normalizeLocale } from '@florin/core/i18n'
import { LOCALE_COOKIE } from '@/lib/locale'

export const dynamic = 'force-dynamic'

export async function POST(request: Request) {
  const body = (await request.json().catch(() => null)) as { locale?: string } | null
  const locale = normalizeLocale(body?.locale)
  const store = await cookies()
  store.set(LOCALE_COOKIE, locale, {
    path: '/',
    maxAge: 60 * 60 * 24 * 365,
    sameSite: 'lax',
  })
  return NextResponse.json({ locale })
}
