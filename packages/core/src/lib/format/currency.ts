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

export function createCurrencyFormatter(locale: string, currency: string): CurrencyFormatter {
  const formatter = new Intl.NumberFormat(locale, { style: 'currency', currency })
  const signedFormatter = new Intl.NumberFormat(locale, {
    style: 'currency',
    currency,
    signDisplay: 'always',
  })
  return {
    format: (amount: number | string | null | undefined) => formatter.format(toNumber(amount)),
    formatSigned: (amount: number | string | null | undefined) =>
      signedFormatter.format(toNumber(amount)),
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
