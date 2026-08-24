'use client'

import {
  Banknote,
  CreditCard,
  Landmark,
  PiggyBank,
  TrendingUp,
  Wallet,
  type LucideIcon,
} from 'lucide-react'
import Link from 'next/link'
import { Amount } from '../../primitives/amount'
import { Row } from '../../primitives/row'
import { useV2T } from '../../i18n/context'
import type { V2Account } from '../../types'

const KIND_ICON: Record<string, LucideIcon> = {
  checking: CreditCard,
  savings: PiggyBank,
  cash: Banknote,
  broker_cash: TrendingUp,
  broker_portfolio: TrendingUp,
  loan: Landmark,
  other: Wallet,
}

const KIND_COLOR: Record<string, string> = {
  checking: 'var(--v2-s1)',
  savings: 'var(--v2-s3)',
  cash: 'var(--v2-s4)',
  broker_cash: 'var(--v2-s2)',
  broker_portfolio: 'var(--v2-s2)',
  loan: 'var(--v2-s5)',
  other: 'var(--v2-s8)',
}

export function accountColor(kind: string): string {
  return KIND_COLOR[kind] ?? 'var(--v2-s8)'
}

export function AccountBubble({ account }: { account: V2Account }) {
  const Icon = KIND_ICON[account.kind] ?? Wallet
  const color = account.displayColor ?? accountColor(account.kind)
  return (
    <span
      className="v2-bubble"
      style={{ background: `color-mix(in oklab, ${color} 15%, transparent)`, color }}
      aria-hidden
    >
      {account.displayIcon ? (
        <span className="text-[17px]">{account.displayIcon}</span>
      ) : (
        <Icon className="h-[18px] w-[18px]" strokeWidth={1.9} />
      )}
    </span>
  )
}

export function AccountRow({
  account,
  href,
  onClick,
}: {
  account: V2Account
  href?: string
  onClick?: () => void
}) {
  const t = useV2T()
  const subtitleBits = [account.institution]
  if (!account.isIncludedInNetWorth) {
    subtitleBits.push(t('v2.accounts.excluded', 'Excluded from net worth'))
  }
  if (account.isArchived) subtitleBits.push(t('v2.accounts.archived', 'Archived'))
  const subtitle = subtitleBits.filter(Boolean).join(' · ') || undefined

  const row = (
    <Row
      leading={<AccountBubble account={account} />}
      title={account.name}
      subtitle={subtitle}
      value={
        <Amount
          value={account.kind === 'loan' ? -(account.debt ?? account.total) : account.total}
          decimals={false}
          tone={account.kind === 'loan' ? 'negative' : 'neutral'}
        />
      }
      meta={
        account.marketValue > 0 && account.balance !== 0 ? (
          <>
            <Amount value={account.balance} decimals={false} tone="muted" />{' '}
            {t('v2.account.cash', 'Cash').toLowerCase()}
          </>
        ) : undefined
      }
      chevron={Boolean(href || onClick)}
      onClick={onClick}
    />
  )

  if (href && !onClick) {
    return (
      <Link href={href as never} className="block">
        {row}
      </Link>
    )
  }
  return row
}
