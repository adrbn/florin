import en from './en.json'
import fr from './fr.json'

const translations: Record<string, Record<string, string>> = { en, fr }

export type SupportedLocale = 'en' | 'fr'

export function normalizeLocale(locale: string | null | undefined): SupportedLocale {
  if (!locale) return 'en'
  return locale.toLowerCase().startsWith('fr') ? 'fr' : 'en'
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
    const raw = dict[key] ?? (typeof varsOrFallback === 'string' ? varsOrFallback : fallback ?? key)
    const vars = typeof varsOrFallback === 'object' ? varsOrFallback : undefined
    return interpolate(raw, vars)
  }
}

export type TFunction = ReturnType<typeof createT>
