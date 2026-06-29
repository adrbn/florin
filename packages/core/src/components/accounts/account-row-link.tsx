'use client'

import { ChevronRight, Wallet } from 'lucide-react'
import Link from 'next/link'
import { formatCurrency } from '../../lib/format/currency'
import { useT } from '../../i18n/context'

interface AccountRowLinkProps {
  id: string
  name: string
  balance: number | string
  icon: string | null
  /** Optional accent color (hex). Used as the icon background tint. */
  color: string | null
  isArchived?: boolean
  /**
   * Signed sum of this account's upcoming `scheduled` (forecast) transactions.
   * When non-zero, a muted "+X prévu" hint renders next to the realized balance.
   */
  scheduledDelta?: number
}

/**
 * One row in the grouped accounts list. The whole row is a link to the
 * account detail page so the user can drill in with a single click — mirrors
 * the YNAB sidebar behavior the user explicitly asked for.
 */
export function AccountRowLink({
  id,
  name,
  balance,
  icon,
  color,
  isArchived = false,
  scheduledDelta = 0,
}: AccountRowLinkProps) {
  const t = useT()
  const tint = color ?? '#10b981' // emerald-500 as a sensible default
  const numericBalance = typeof balance === 'number' ? balance : Number(balance)
  const isNegative = numericBalance < 0
  const hasScheduled = Number.isFinite(scheduledDelta) && Math.abs(scheduledDelta) >= 0.005
  return (
    <Link
      href={`/accounts/${id}`}
      className={`group flex items-center gap-3 px-3 py-2.5 transition-colors hover:bg-muted/60 ${
        isArchived ? 'opacity-60' : ''
      }`}
    >
      <span
        className="flex h-7 w-7 shrink-0 items-center justify-center rounded-md text-[13px]"
        style={{
          backgroundColor: `${tint}1f`, // ~12% alpha, calmer than the previous 33/20%
          color: tint,
        }}
        aria-hidden
      >
        {icon ?? <Wallet className="h-3.5 w-3.5" />}
      </span>
      <span className="flex-1 truncate text-sm font-medium text-foreground">{name}</span>
      <span className="flex shrink-0 flex-col items-end leading-tight">
        <span
          className={`text-sm font-medium ${
            isNegative ? 'text-destructive' : 'text-foreground'
          }`}
        >
          {formatCurrency(numericBalance)}
        </span>
        {hasScheduled && (
          <span className="text-[10px] font-medium text-muted-foreground" title={name}>
            {scheduledDelta >= 0
              ? t(
                  'accounts.scheduledHint',
                  { amount: formatCurrency(scheduledDelta) },
                  '+{amount} planned',
                )
              : t(
                  'accounts.scheduledHint',
                  { amount: formatCurrency(scheduledDelta) },
                  '+{amount} planned',
                ).replace('+', '')}
          </span>
        )}
      </span>
      <ChevronRight className="h-3.5 w-3.5 shrink-0 text-muted-foreground/50 transition-transform group-hover:translate-x-0.5" />
    </Link>
  )
}
