'use client'

import { ChevronDown } from 'lucide-react'
import { useState } from 'react'
import { AccountRowLink } from '@/components/accounts/account-row-link'
import { Card } from '@/components/ui/card'
import { formatCurrency } from '@/lib/format/currency'

export interface GroupedAccount {
  id: string
  name: string
  kind: string
  currentBalance: string | number
  displayIcon: string | null
  displayColor: string | null
  isArchived: boolean
}

interface AccountsGroupedListProps {
  accounts: ReadonlyArray<GroupedAccount>
}

const KIND_LABEL: Record<string, string> = {
  checking: 'Cash',
  savings: 'Cash',
  cash: 'Cash',
  loan: 'Loan',
  broker_cash: 'Investing',
  broker_portfolio: 'Investing',
  other: 'Other',
}

const KIND_ORDER: ReadonlyArray<string> = ['Cash', 'Investing', 'Loan', 'Other']

interface GroupBucket {
  label: string
  accounts: GroupedAccount[]
  total: number
}

function bucketize(accounts: ReadonlyArray<GroupedAccount>): GroupBucket[] {
  const map = new Map<string, GroupBucket>()
  for (const a of accounts) {
    const label = KIND_LABEL[a.kind] ?? 'Other'
    const bucket = map.get(label) ?? { label, accounts: [], total: 0 }
    bucket.accounts.push(a)
    bucket.total += Number(a.currentBalance)
    map.set(label, bucket)
  }
  return KIND_ORDER.flatMap((label) => {
    const b = map.get(label)
    return b ? [b] : []
  })
}

/**
 * Grouped, collapsible list of accounts. Mirrors the look the user
 * sketched: a kind label with subtotal at the top, then one clickable row
 * per account inside a rounded card. State is local — no need to round-trip
 * to the server for collapsed/expanded.
 */
export function AccountsGroupedList({ accounts }: AccountsGroupedListProps) {
  const buckets = bucketize(accounts)
  const [collapsed, setCollapsed] = useState<Record<string, boolean>>({})

  const toggle = (label: string) => {
    setCollapsed((prev) => ({ ...prev, [label]: !prev[label] }))
  }

  if (accounts.length === 0) {
    return <Card className="py-12 text-center text-sm text-muted-foreground">No accounts yet.</Card>
  }

  return (
    <div className="space-y-3">
      {buckets.map((bucket) => {
        const isCollapsed = collapsed[bucket.label] === true
        const isNegative = bucket.total < 0
        return (
          <section key={bucket.label} className="space-y-1.5">
            <button
              type="button"
              onClick={() => toggle(bucket.label)}
              className="flex w-full items-center gap-2 px-1 text-left"
            >
              <ChevronDown
                className={`h-3.5 w-3.5 text-muted-foreground transition-transform ${
                  isCollapsed ? '-rotate-90' : ''
                }`}
              />
              <span className="text-[11px] font-semibold uppercase tracking-wider text-muted-foreground">
                {bucket.label}
              </span>
              <span
                className={`ml-auto text-sm font-semibold ${
                  isNegative ? 'text-destructive' : 'text-foreground'
                }`}
              >
                {formatCurrency(bucket.total)}
              </span>
            </button>
            {!isCollapsed && (
              <Card className="divide-y divide-border/60 overflow-hidden p-0">
                {bucket.accounts.map((a) => (
                  <AccountRowLink
                    key={a.id}
                    id={a.id}
                    name={a.name}
                    balance={a.currentBalance}
                    icon={a.displayIcon}
                    color={a.displayColor}
                    isArchived={a.isArchived}
                  />
                ))}
              </Card>
            )}
          </section>
        )
      })}
    </div>
  )
}
