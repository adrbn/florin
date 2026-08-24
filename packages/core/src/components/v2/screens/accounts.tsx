'use client'

import { useMemo } from 'react'
import { Landmark, Plus, Wallet } from 'lucide-react'
import Link from 'next/link'
import { useV2T } from '../i18n/context'
import { useMoney } from '../lib/config'
import { Amount } from '../primitives/amount'
import { Card, Empty, Section } from '../primitives/atoms'
import { RowGroup } from '../primitives/row'
import { Screen } from '../shell/screen'
import { V2_BASE } from '../shell/nav'
import { AccountRow } from './parts/account-row'
import type { V2Account } from '../types'

/**
 * Accounts are grouped by role rather than listed flat: on a phone, "how much
 * is liquid vs invested vs owed" is the question, and a flat list forces the
 * user to do that arithmetic in their head every time.
 */
const GROUP_ORDER = ['checking', 'savings', 'cash', 'broker', 'loan', 'other'] as const
type GroupKey = (typeof GROUP_ORDER)[number]

function groupOf(kind: string): GroupKey {
  if (kind === 'broker_cash' || kind === 'broker_portfolio') return 'broker'
  return (GROUP_ORDER as ReadonlyArray<string>).includes(kind) ? (kind as GroupKey) : 'other'
}

export function AccountsScreen({
  accounts,
  net,
  bankSyncConfigured,
}: {
  accounts: V2Account[]
  /** Authoritative net worth from `getNetWorth()` — see V2Account.netContribution. */
  net: number
  bankSyncConfigured: boolean
}) {
  const t = useV2T()
  const m = useMoney()

  const groups = useMemo(() => {
    const map = new Map<GroupKey, V2Account[]>()
    for (const a of accounts) {
      const key = groupOf(a.kind)
      const list = map.get(key)
      if (list) list.push(a)
      else map.set(key, [a])
    }
    return map
  }, [accounts])

  const labels: Record<GroupKey, string> = {
    checking: t('v2.accounts.group.checking', 'Current accounts'),
    savings: t('v2.accounts.group.savings', 'Savings'),
    cash: t('v2.accounts.group.cash', 'Cash'),
    broker: t('v2.accounts.group.broker', 'Investments'),
    loan: t('v2.accounts.group.loan', 'Loans'),
    other: t('v2.accounts.group.other', 'Other'),
  }

  const hero = (
    <div className="v2-gutter flex flex-col gap-1 pb-2">
      <span className="v2-eyebrow">{t('v2.accounts.title', 'Accounts')}</span>
      <Amount value={net} className="text-[38px] font-light leading-none tracking-[-0.035em]" />
      <span className="v2-sub">
        {t(
          'v2.accounts.subtitle',
          { count: accounts.filter((a) => !a.isArchived).length, amount: m.compact(net) },
          '{count} accounts · {amount}',
        )}
      </span>
    </div>
  )

  if (accounts.length === 0) {
    return (
      <Screen title={t('v2.accounts.title', 'Accounts')} hero={hero}>
        <Empty
          icon={<Wallet className="h-5 w-5" />}
          title={t('v2.accounts.empty', 'No accounts yet')}
          hint={t('v2.accounts.emptyHint', 'Add an account or connect your bank to get started.')}
          action={
            <Link href={`${V2_BASE}/accounts/connect` as never} className="v2-btn v2-btn-primary">
              <Plus className="h-4 w-4" />
              {t('v2.accounts.connect', 'Connect a bank')}
            </Link>
          }
        />
      </Screen>
    )
  }

  return (
    <Screen title={t('v2.accounts.title', 'Accounts')} hero={hero}>
      {GROUP_ORDER.filter((k) => groups.has(k)).map((key) => {
        const list = groups.get(key)!
        const subtotal = list.reduce((s, a) => s + a.netContribution, 0)
        return (
          <Section
            key={key}
            title={labels[key]}
            action={
              <Amount
                value={subtotal}
                decimals={false}
                tone={key === 'loan' ? 'negative' : 'muted'}
                className="text-[12px]"
              />
            }
          >
            <div className="v2-gutter">
              <RowGroup>
                {list.map((a) => (
                  <AccountRow key={a.id} account={a} href={`${V2_BASE}/accounts/${a.id}`} />
                ))}
              </RowGroup>
            </div>
          </Section>
        )
      })}

      <div className="v2-gutter">
        <Link href={`${V2_BASE}/accounts/connect` as never} className="block">
          <Card className="flex items-center gap-3 p-3.5">
            <span className="v2-bubble bg-[var(--v2-accent-soft)] text-[var(--v2-accent-text)]">
              <Landmark className="h-4 w-4" />
            </span>
            <span className="flex min-w-0 flex-1 flex-col">
              <span className="v2-title">{t('v2.accounts.connect', 'Connect a bank')}</span>
              <span className="v2-sub truncate">
                {bankSyncConfigured
                  ? t('v2.accounts.connectHint', 'Sync your transactions automatically')
                  : t('v2.connect.notConfigured', "Bank sync isn't configured yet.")}
              </span>
            </span>
            <Plus className="h-4 w-4 flex-none text-[var(--v2-text-3)]" />
          </Card>
        </Link>
      </div>
    </Screen>
  )
}
