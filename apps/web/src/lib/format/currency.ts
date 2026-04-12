import { createCurrencyFormatter } from '@florin/core/lib/format'

const { format, formatSigned } = createCurrencyFormatter('fr-FR', 'EUR')

export const formatCurrency = format
export const formatCurrencySigned = formatSigned
