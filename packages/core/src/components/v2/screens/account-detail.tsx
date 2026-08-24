'use client'

import { useMemo, useState } from 'react'
import { CircleAlert } from 'lucide-react'
import { useV2T } from '../i18n/context'
import { useMoney, useV2Config } from '../lib/config'
import { dayLabel, shortDate } from '../lib/format'
import { Amount, DeltaChip, HeroAmount } from '../primitives/amount'
import { Card, Empty, Pill, Section } from '../primitives/atoms'
import { RowGroup } from '../primitives/row'
import { Sparkline, type SparkPoint } from '../primitives/sparkline'
import { Screen } from '../shell/screen'
import { V2_BASE } from '../shell/nav'
import { AccountBubble } from './parts/account-row'
import { CategoryPickerSheet } from './parts/category-picker-sheet'
import { TxDetailSheet, type TxDetailActions } from './parts/tx-detail-sheet'
import { TxRow } from './parts/tx-row'
import type { V2Account, V2Category, V2Holding, V2Tx } from '../types'

export interface AccountDetailData {
  account: V2Account
  transactions: V2Tx[]
  holdings: V2Holding[]
  valuation: {
    marketValue: number
    costBasis: number
    plusValue: number
    cash: number
  } | null
}

/**
 * Walk the account balance backwards through its transactions to get a curve.
 *
 * There is no per-account time series in the query layer, and adding one for a
 * UI experiment would mean touching both DB packages. The transactions are
 * already on this screen, and the same backward walk the global patrimony
 * query performs works identically for one account — so the chart costs
 * nothing extra.
 */
function seriesFromTransactions(current: number, txs: V2Tx[]): SparkPoint[] {
  const cleared = txs
    .filter((t) => !t.isScheduled)
    .slice()
    .sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime())
  if (cleared.length < 2) return []

  const points: SparkPoint[] = []
  let balance = current
  for (const tx of cleared) {
    const ms = new Date(tx.date).getTime()
    points.push({ x: ms, y: balance, label: tx.date })
    balance -= tx.amount
  }
  points.push({ x: points[points.length - 1]!.x - 86_400_000, y: balance })
  return points.reverse()
}

export function AccountDetailScreen({
  data,
  txActions,
  categories = [],
}: {
  data: AccountDetailData
  txActions?: TxDetailActions
  categories?: V2Category[]
}) {
  const t = useV2T()
  const m = useMoney()
  const { tag } = useV2Config()
  const [scrub, setScrub] = useState<SparkPoint | null>(null)
  const [detail, setDetail] = useState<V2Tx | null>(null)
  const [picking, setPicking] = useState<V2Tx | null>(null)
  const { account, transactions, holdings, valuation } = data

  const spark = useMemo(
    () => seriesFromTransactions(account.balance, transactions),
    [account.balance, transactions],
  )

  const isLoan = account.kind === 'loan'
  const shown = scrub ? scrub.y : isLoan ? (account.debt ?? account.total) : account.total
  const first = spark[0]?.y ?? shown

  const hero = (
    <div className="flex flex-col gap-3 pb-1">
      <div className="v2-gutter flex items-center gap-3">
        <AccountBubble account={account} />
        <div className="flex min-w-0 flex-col">
          <span className="v2-title truncate">{account.name}</span>
          {account.institution && <span className="v2-sub truncate">{account.institution}</span>}
        </div>
      </div>

      <div className="v2-gutter flex flex-col gap-1">
        <span className="v2-eyebrow">
          {isLoan ? t('v2.account.loanRemaining', 'Outstanding') : t('v2.account.balance', 'Balance')}
        </span>
        <HeroAmount value={isLoan ? -shown : shown} />
        <div className="flex min-h-[20px] items-center gap-2">
          {scrub ? (
            <DeltaChip
              value={scrub.y - first}
              suffix={scrub.label ? shortDate(new Date(scrub.label), tag) : undefined}
            />
          ) : (
            <span className="v2-sub">
              {account.lastSyncedAt
                ? `${t('v2.account.lastSync', 'Last sync')} · ${shortDate(new Date(account.lastSyncedAt), tag)}`
                : t('v2.overview.neverSynced', 'Never synced')}
            </span>
          )}
        </div>
      </div>

      {spark.length > 1 && (
        <Sparkline
          data={spark}
          height={110}
          color={isLoan ? 'var(--v2-neg)' : 'var(--v2-accent)'}
          onScrub={(p) => setScrub(p)}
          ariaLabel={account.name}
        />
      )}
    </div>
  )

  return (
    <Screen title={account.name} hero={hero} back={`${V2_BASE}/accounts`}>
      {valuation && (
        <div className="v2-gutter grid grid-cols-2 gap-3">
          <Card className="flex flex-col gap-1 p-4">
            <span className="v2-eyebrow">{t('v2.account.marketValue', 'Market value')}</span>
            <Amount
              value={valuation.marketValue}
              decimals={false}
              className="text-[22px] font-light leading-tight"
            />
            <span className="v2-micro">
              {t('v2.account.costBasis', 'Invested')}{' '}
              <Amount value={valuation.costBasis} decimals={false} tone="muted" />
            </span>
          </Card>
          <Card className="flex flex-col gap-1 p-4">
            <span className="v2-eyebrow">{t('v2.account.plusValue', 'Gain')}</span>
            <Amount
              value={valuation.plusValue}
              signed
              decimals={false}
              tone="auto"
              className="text-[22px] font-light leading-tight"
            />
            <span className="v2-micro">
              {t('v2.account.cash', 'Cash')}{' '}
              <Amount value={valuation.cash} decimals={false} tone="muted" />
            </span>
          </Card>
        </div>
      )}

      {isLoan && account.loan && (
        <div className="v2-gutter">
          <Card className="flex flex-wrap gap-2 p-4">
            {account.loan.rate !== null && (
              <Pill>
                {t('v2.account.loanRate', 'Rate')} {m.pct(account.loan.rate, 2)}
              </Pill>
            )}
            {account.loan.monthlyPayment !== null && (
              <Pill>
                {t('v2.account.loanMonthly', 'Monthly payment')}{' '}
                <Amount value={account.loan.monthlyPayment} decimals={false} />
              </Pill>
            )}
            {account.loan.termMonths !== null && (
              <Pill>
                {account.loan.termMonths} {t('v2.common.months', 'months')}
              </Pill>
            )}
          </Card>
        </div>
      )}

      {holdings.length > 0 && (
        <Section title={t('v2.account.holdings', 'Holdings')}>
          <div className="v2-gutter">
            <RowGroup>
              {holdings.map((h) => (
                <div key={h.id} className="v2-row">
                  <span className="flex min-w-0 flex-1 flex-col gap-0.5">
                    <span className="v2-title flex items-center gap-1.5 truncate">
                      {h.label}
                      {h.isStale && (
                        <CircleAlert
                          aria-label={t('v2.account.stalePrice', 'Stale price')}
                          className="h-3.5 w-3.5 flex-none text-[var(--v2-warn)]"
                        />
                      )}
                    </span>
                    <span className="v2-sub">
                      <span className="v2-num">{h.quantity}</span>
                      {h.lastPrice !== null && <> × {m.fmt(h.lastPrice)}</>}
                    </span>
                  </span>
                  <span className="flex flex-none flex-col items-end gap-0.5">
                    <Amount value={h.marketValue} decimals={false} className="text-[15px]" />
                    <span className="v2-micro">
                      <Amount value={h.plusValue} signed decimals={false} tone="auto" />
                      {h.plusValuePct !== null && <> · {m.pct(h.plusValuePct, 1)}</>}
                    </span>
                  </span>
                </div>
              ))}
            </RowGroup>
          </div>
        </Section>
      )}

      <Section title={t('v2.account.transactions', 'Transactions')}>
        <div className="v2-gutter">
          <RowGroup>
            {transactions.length === 0 ? (
              <Empty title={t('v2.activity.empty', 'No transactions')} />
            ) : (
              transactions
                .slice(0, 60)
                .map((tx) => (
                  <TxRow
                    key={tx.id}
                    tx={tx}
                    secondary={dayLabel(new Date(tx.date), tag, {
                      today: t('v2.common.today', 'Today'),
                      yesterday: t('v2.common.yesterday', 'Yesterday'),
                    })}
                    onClick={txActions ? () => setDetail(tx) : undefined}
                  />
                ))
            )}
          </RowGroup>
        </div>
      </Section>

      {txActions && (
        <>
          <TxDetailSheet
            tx={detail}
            onClose={() => setDetail(null)}
            onCategorize={() => {
              const tx = detail
              setDetail(null)
              setPicking(tx)
            }}
            actions={txActions}
          />
          <CategoryPickerSheet
            open={picking !== null}
            onClose={() => setPicking(null)}
            categories={categories}
            currentId={picking?.categoryId ?? null}
            onPick={async (categoryId) => {
              if (picking) await txActions.updateTransactionCategory(picking.id, categoryId)
            }}
          />
        </>
      )}
    </Screen>
  )
}
