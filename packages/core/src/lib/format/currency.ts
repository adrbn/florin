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
 * Default formatter using EUR / fr-FR locale.
 * Components that need a different currency should accept a `CurrencyFormatter`
 * prop instead of calling these directly.
 */
const defaultFormatter = createCurrencyFormatter('fr-FR', 'EUR')
export const formatCurrency = defaultFormatter.format
export const formatCurrencySigned = defaultFormatter.formatSigned
