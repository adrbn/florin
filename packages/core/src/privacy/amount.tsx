'use client'
import { formatCurrency, formatCurrencySigned } from '../lib/format/currency'
import { maskAmount, usePrivacy } from './context'

interface AmountProps {
  value: number | string | null | undefined
  signed?: boolean
  className?: string
  /** Optional override — render the already-formatted string, just mask when hidden. */
  formatted?: string
}

/**
 * Render a currency amount that respects the user's privacy mode. When hidden,
 * digits are replaced with bullets while the currency symbol and separators
 * stay in place — layouts don't jump and the currency is still visible.
 */
export function Amount({ value, signed = false, className, formatted }: AmountProps) {
  const { hidden } = usePrivacy()
  const raw = formatted ?? (signed ? formatCurrencySigned(value) : formatCurrency(value))
  const text = hidden ? maskAmount(raw) : raw
  return <span className={className}>{text}</span>
}
