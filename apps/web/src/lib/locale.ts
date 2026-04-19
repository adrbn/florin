import { cookies } from 'next/headers'
import { createT, normalizeLocale, type SupportedLocale } from '@florin/core/i18n'

export const LOCALE_COOKIE = 'florin-locale'

export async function getUserLocale(): Promise<SupportedLocale> {
  try {
    const store = await cookies()
    const raw = store.get(LOCALE_COOKIE)?.value
    return normalizeLocale(raw)
  } catch {
    return 'en'
  }
}

export async function getServerT() {
  const locale = await getUserLocale()
  return createT(locale)
}
