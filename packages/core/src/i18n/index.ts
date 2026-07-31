import en from './en.json'
import fr from './fr.json'
import nl from './nl.json'

const translations: Record<string, Record<string, string>> = { en, fr, nl }

export type SupportedLocale = 'en' | 'fr' | 'nl'

/** Every locale the UI ships, in the order the language picker lists them. */
export const SUPPORTED_LOCALES: ReadonlyArray<{
  code: SupportedLocale
  /** Short badge shown in the sidebar switcher. */
  label: string
  /** Endonym — a language reads best named in its own language. */
  name: string
}> = [
  { code: 'fr', label: 'FR', name: 'Français' },
  { code: 'en', label: 'EN', name: 'English' },
  { code: 'nl', label: 'NL', name: 'Nederlands' },
]

/**
 * BCP-47 tag per locale, for Intl (currency, dates, number grouping). Kept here
 * so call sites stop hand-rolling `toLocaleTag(locale)`
 * ternaries, which silently render any third language with US formatting.
 */
const LOCALE_TAGS: Record<SupportedLocale, string> = {
  en: 'en-US',
  fr: 'fr-FR',
  nl: 'nl-NL',
}

export function normalizeLocale(locale: string | null | undefined): SupportedLocale {
  if (!locale) return 'en'
  const lower = locale.toLowerCase()
  return SUPPORTED_LOCALES.find((l) => lower.startsWith(l.code))?.code ?? 'en'
}

/** Locale string (or anything loosely locale-ish) → BCP-47 tag for Intl. */
export function toLocaleTag(locale: string | null | undefined): string {
  return LOCALE_TAGS[normalizeLocale(locale)]
}

function interpolate(template: string, vars?: Record<string, string | number>): string {
  if (!vars) return template
  return template.replace(/\{(\w+)\}/g, (_, key: string) => {
    const v = vars[key]
    return v === undefined ? `{${key}}` : String(v)
  })
}

export function createT(locale: string) {
  const lang = normalizeLocale(locale)
  const dict = translations[lang] ?? translations.en!
  return function t(key: string, varsOrFallback?: Record<string, string | number> | string, fallback?: string): string {
    // Fall back to English before the inline default, so a key that a newer
    // translation hasn't caught up on still renders a real sentence.
    const raw =
      dict[key] ??
      translations.en?.[key] ??
      (typeof varsOrFallback === 'string' ? varsOrFallback : fallback ?? key)
    const vars = typeof varsOrFallback === 'object' ? varsOrFallback : undefined
    return interpolate(raw, vars)
  }
}

export type TFunction = ReturnType<typeof createT>
