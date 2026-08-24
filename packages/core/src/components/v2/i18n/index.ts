import { createT, normalizeLocale, type TFunction } from '../../../i18n'
import en from './en.json'
import fr from './fr.json'
import nl from './nl.json'

/**
 * v2 ships its own dictionary rather than adding ~200 keys to the shared
 * fr/en/nl files. Those are locked by a parity test and belong to the shipping
 * UI; the v2 redesign is a separate surface and should be removable in one
 * `rm -rf` if it does not pan out.
 *
 * Lookup order: v2 locale dict → v2 English → the *base* app dictionary →
 * the inline fallback passed at the call site. The base-dictionary step means
 * v2 can reuse the 910 strings that already exist (category names, account
 * kinds, settings labels) without copying them.
 */
const V2_DICTS: Record<string, Record<string, string>> = { en, fr, nl }

function interpolate(template: string, vars?: Record<string, string | number>): string {
  if (!vars) return template
  return template.replace(/\{(\w+)\}/g, (_, key: string) => {
    const v = vars[key]
    return v === undefined ? `{${key}}` : String(v)
  })
}

/**
 * Plural-aware key lookup.
 *
 * A counted string needs at least two forms — "1 opération" vs "2 opérations"
 * — and a flat dictionary silently renders the plural for every count. Any key
 * may ship a `<key>_one` sibling; when the interpolated `count` resolves to the
 * "one" category for the active locale, that variant wins. Locales without a
 * distinct singular simply never define the sibling. French counts 0 as "one"
 * (0 opération), English does not — `Intl.PluralRules` already knows this, so
 * we do not hardcode it.
 */
function pluralKey(
  key: string,
  dict: Record<string, string>,
  lang: string,
  vars?: Record<string, string | number>,
): string {
  const count = vars?.count
  if (typeof count !== 'number') return key
  const variant = `${key}_${new Intl.PluralRules(lang).select(count)}`
  return dict[variant] !== undefined ? variant : key
}

export function createV2T(locale: string): TFunction {
  const lang = normalizeLocale(locale)
  const dict = V2_DICTS[lang] ?? V2_DICTS.en!
  const base = createT(locale)
  return function t(
    key: string,
    varsOrFallback?: Record<string, string | number> | string,
    fallback?: string,
  ): string {
    const early = typeof varsOrFallback === 'object' ? varsOrFallback : undefined
    const resolved = pluralKey(key, dict, lang, early)
    const raw = dict[resolved] ?? V2_DICTS.en?.[pluralKey(key, V2_DICTS.en!, 'en', early)]
    if (raw === undefined) {
      // Not a v2 string — defer to the shared app dictionary, which also
      // handles the inline-default fallback.
      return base(key, varsOrFallback as never, fallback)
    }
    const vars = typeof varsOrFallback === 'object' ? varsOrFallback : undefined
    return interpolate(raw, vars)
  }
}

export { V2_DICTS }
