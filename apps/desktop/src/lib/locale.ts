import { eq } from 'drizzle-orm'
import { createT, normalizeLocale, type SupportedLocale } from '@florin/core/i18n'
import { db } from '@/db/client'
import { settings } from '@/db/schema'

export async function getUserLocale(): Promise<SupportedLocale> {
  try {
    const row = await db
      .select()
      .from(settings)
      .where(eq(settings.key, 'user_locale'))
      .get()
    return normalizeLocale(row?.value)
  } catch {
    return 'en'
  }
}

export async function getServerT() {
  const locale = await getUserLocale()
  return createT(locale)
}
