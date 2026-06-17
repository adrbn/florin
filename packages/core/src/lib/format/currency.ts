function toNumber(amount: number | string | null | undefined): number {
  if (amount === null || amount === undefined) {
    return 0
  }
  if (typeof amount === 'number') {
    return amount
  }
  const parsed = Number(amount)
  return Number.isFinite(parsed) ? parsed : 0
}

export interface CurrencyFormatter {
  format: (amount: number | string | null | undefined) => string
  formatSigned: (amount: number | string | null | undefined) => string
}

/**
 * French Intl.NumberFormat uses U+202F (NARROW NO-BREAK SPACE) between
 * thousands, which renders as a barely-visible hair gap at large sizes
 * ("18000€" instead of "18 000 €"). Replace it with U+00A0 (NO-BREAK
 * SPACE) so thousands groups actually read as grouped, and currency/sign
 * markers stay on the same line.
 */
function widenGroupSeparator(s: string): string {
  return s.replace(/\u202F/g, '\u00A0')
}

export function createCurrencyFormatter(locale: string, currency: string): CurrencyFormatter {
  const formatter = new Intl.NumberFormat(locale, { style: 'currency', currency })
  const signedFormatter = new Intl.NumberFormat(locale, {
    style: 'currency',
    currency,
    signDisplay: 'always',
  })
  return {
    format: (amount: number | string | null | undefined) =>
      widenGroupSeparator(formatter.format(toNumber(amount))),
    formatSigned: (amount: number | string | null | undefined) =>
      widenGroupSeparator(signedFormatter.format(toNumber(amount))),
  }
}

/**
 * Mutable default formatter — starts as EUR / fr-FR but can be reconfigured
 * at runtime via `setCurrencyConfig()` for single-user desktop apps.
 */
let activeFormatter = createCurrencyFormatter('fr-FR', 'EUR')

export function setCurrencyConfig(locale: string, currency: string): void {
  activeFormatter = createCurrencyFormatter(locale, currency)
}

export const formatCurrency: CurrencyFormatter['format'] = (...args) => activeFormatter.format(...args)
export const formatCurrencySigned: CurrencyFormatter['formatSigned'] = (...args) =>
  activeFormatter.formatSigned(...args)

/**
 * Parse a free-text numeric field into a number. Accepts both '.' and ','
 * as the decimal separator and tolerates the transient states a user passes
 * through while typing ('', '-', '.', '-.') by returning the supplied
 * fallback instead of coercing to 0.
 *
 * This is the antidote to the "zero-on-clear" bug: bind numeric `<input>`s to
 * a *string* state and only run the raw text through this helper where a
 * number is actually needed (a computation). Clearing the box then leaves it
 * empty instead of snapping back to a stubborn "0" the user has to delete.
 */
export function parseDecimalInput(value: string, fallback = 0): number {
  const trimmed = value.trim().replace(/\s/g, '').replace(',', '.')
  if (trimmed === '' || trimmed === '-' || trimmed === '.' || trimmed === '-.') {
    return fallback
  }
  const parsed = Number(trimmed)
  return Number.isFinite(parsed) ? parsed : fallback
}
