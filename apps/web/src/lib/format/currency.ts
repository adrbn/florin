const eurFormatter = new Intl.NumberFormat('fr-FR', {
  style: 'currency',
  currency: 'EUR',
})

const eurSignedFormatter = new Intl.NumberFormat('fr-FR', {
  style: 'currency',
  currency: 'EUR',
  signDisplay: 'always',
})

export function formatCurrency(amount: number | string | null | undefined): string {
  const value = toNumber(amount)
  return eurFormatter.format(value)
}

export function formatCurrencySigned(amount: number | string | null | undefined): string {
  const value = toNumber(amount)
  return eurSignedFormatter.format(value)
}

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
