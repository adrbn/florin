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
