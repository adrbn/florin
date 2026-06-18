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

/**
 * Deploy-time currency for the whole instance. Florin web is single-tenant,
 * so currency is one global value configured via the `APP_CURRENCY` env var
 * (ISO 4217, e.g. `USD`, `GBP`). Defaults to `EUR` to preserve the original
 * behaviour when unset. The locale comes from the user's language preference.
 */
export const APP_CURRENCY = process.env.APP_CURRENCY?.trim() || 'EUR'

export async function getCurrencyConfig(): Promise<{ locale: string; currency: string }> {
  const locale = await getUserLocale()
  return { locale, currency: APP_CURRENCY }
}
