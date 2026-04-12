import en from './en.json'
import fr from './fr.json'

const translations: Record<string, Record<string, string>> = { en, fr }

export function createT(locale: string) {
  const lang = locale.startsWith('fr') ? 'fr' : 'en'
  const dict = translations[lang] ?? translations.en!
  return function t(key: string, fallback?: string): string {
    return dict[key] ?? fallback ?? key
  }
}

export type TFunction = ReturnType<typeof createT>
