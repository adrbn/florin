import { cookies } from 'next/headers'
import { createT, normalizeLocale, type SupportedLocale } from '@florin/core/i18n'

export const LOCALE_COOKIE = 'florin-locale'

/**
 * Deploy-time default language, for callers with no cookie.
 *
 * Florin web is single-tenant, so the instance has one language the same way it
 * has one currency. It matters beyond taste: the native client authenticates
 * with a bearer token and therefore sends no cookie, so without this every API
 * response came back in English regardless of what the browser was set to.
 */
export const APP_LOCALE = normalizeLocale(process.env.APP_LOCALE?.trim())

export async function getUserLocale(): Promise<SupportedLocale> {
  try {
    const store = await cookies()
    const raw = store.get(LOCALE_COOKIE)?.value
    return raw ? normalizeLocale(raw) : APP_LOCALE
  } catch {
    return APP_LOCALE
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
