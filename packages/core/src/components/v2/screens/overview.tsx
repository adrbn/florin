'use client'

import { useMemo, useState } from 'react'
import { ArrowUpRight, Inbox, RefreshCw, Target } from 'lucide-react'
import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { useTransition } from 'react'
import type {
  GoalProjection,
  LeftToSpend,
  NetWorthAllocation,
  NetWorth,
  PatrimonyPoint,
  SavingsRates,
} from '../../../types'
import { computeMonthForecast } from '../../../lib/reflect/insights'
import { useV2T } from '../i18n/context'
import { useMoney, useV2Config } from '../lib/config'
import { dayLabel, seriesVar, shortDate } from '../lib/format'
import { RANGES, sliceRange, toSparkPoints, type Range } from '../lib/series'
import { Amount, DeltaChip, HeroAmount } from '../primitives/amount'
import { Card, Empty, Pill, Section, Track } from '../primitives/atoms'
import { Donut, DonutLegend } from '../primitives/donut'
import { Row, RowGroup } from '../primitives/row'
import { Segmented } from '../primitives/segmented'
import { Sparkline, type SparkPoint } from '../primitives/sparkline'
import { Screen } from '../shell/screen'
import { V2_BASE } from '../shell/nav'
import { AccountRow } from './parts/account-row'
import { CategoryPickerSheet } from './parts/category-picker-sheet'
import { TxDetailSheet, type TxDetailActions } from './parts/tx-detail-sheet'
import { TxRow } from './parts/tx-row'
import type { V2Account, V2Category, V2Tx } from '../types'
import { cn } from '../../../lib/utils'

export interface OverviewData {
  netWorth: NetWorth
  /** Daily patrimony curve, already downsampled by the page adapter. */
  series: PatrimonyPoint[]
  leftToSpend: LeftToSpend
  burnThisMonth: number
  burnAvg6: number
  savings: SavingsRates
  allocation: NetWorthAllocation
  accounts: V2Account[]
  recent: V2Tx[]
  goal: GoalProjection | null
  reviewCount: number
  monthlyTrend: number
  lastSyncedAt: string | null
  hasBankSync: boolean
  /**
   * True when this month's salary has not landed yet, so `leftToSpend.monthIncome`
   * is last month's standing in for it.
   *
   * The substitution is deliberate — before payday the alternative is a
   * "left to spend" of minus everything — but labelling the result "revenus du
   * mois" without saying so makes the app claim money that has not arrived.
   */
  incomeIsEstimated: boolean
}

export function OverviewScreen({
  data,
  onSyncAll,
  txActions,
  categories = [],
}: {
  data: OverviewData
  onSyncAll?: () => Promise<unknown>
  /** Enables tap-to-inspect on the recent-activity rows. */
  txActions?: TxDetailActions
  categories?: V2Category[]
}) {
  const t = useV2T()
  const m = useMoney()
  const { tag } = useV2Config()
  const [range, setRange] = useState<Range>('1y')
  const [scrub, setScrub] = useState<SparkPoint | null>(null)
  const [detail, setDetail] = useState<V2Tx | null>(null)
  const [picking, setPicking] = useState<V2Tx | null>(null)

  const windowed = useMemo(() => sliceRange(data.series, range), [data.series, range])
  const spark = useMemo(() => toSparkPoints(windowed), [windowed])

  // The hero prints the scrubbed value while a finger is down, and the delta
  // becomes "since the start of this window" rather than "over a month" —
  // otherwise the two numbers describe different periods and quietly lie.
  const first = windowed[0]?.balance ?? data.netWorth.net
  const scrubbing = scrub !== null
  const shownValue = scrubbing ? scrub.y : data.netWorth.net
  const shownDelta = scrubbing ? scrub.y - first : data.netWorth.net - (data.netWorth.netMonthAgo ?? data.netWorth.net)
  const deltaPct = first !== 0 ? ((shownValue - first) / Math.abs(first)) * 100 : null

  const forecast = computeMonthForecast(data.leftToSpend)
  const lts = data.leftToSpend

  // First of the current month, for the "spent this month" tile's filter link.
  const now = new Date()
  const monthStart = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-01`

  const hero = (
    <div className="flex flex-col gap-3 pb-1">
      <div className="v2-gutter flex flex-col gap-1.5">
        <span className="v2-eyebrow">{t('v2.overview.netWorth', 'Net worth')}</span>
        <HeroAmount value={shownValue} />
        <div className="flex min-h-[20px] items-center gap-2">
          <DeltaChip
            value={shownDelta}
            pct={scrubbing ? deltaPct : null}
            suffix={
              scrubbing
                ? scrub.label
                  ? shortDate(new Date(scrub.label), tag)
                  : undefined
                : t('v2.overview.sinceLastMonth', 'over a month')
            }
          />
        </div>
      </div>

      <Sparkline
        data={spark}
        height={148}
        baseline
        onScrub={(p) => setScrub(p)}
        ariaLabel={t('v2.overview.netWorth', 'Net worth')}
      />

      <div className="v2-gutter">
        <Segmented
          value={range}
          onChange={(r) => {
            setRange(r)
            setScrub(null)
          }}
          options={RANGES.map((r) => ({ value: r.value, label: t(r.key, r.fallback) }))}
        />
      </div>

      <div className="v2-gutter flex flex-wrap items-center gap-2">
        <Pill>
          {t('v2.overview.gross', 'Gross')} <Amount value={data.netWorth.gross} decimals={false} />
        </Pill>
        {data.netWorth.liability > 0 && (
          <Pill tone="negative">
            {t('v2.overview.debt', 'Debt')}{' '}
            <Amount value={data.netWorth.liability} decimals={false} tone="negative" />
          </Pill>
        )}
        {data.monthlyTrend !== 0 && (
          <Pill tone={data.monthlyTrend > 0 ? 'positive' : 'negative'}>
            {m.fmt(data.monthlyTrend, { signed: true, decimals: false })}
            {t('v2.common.perMonth', '/mo')}
          </Pill>
        )}
      </div>
    </div>
  )

  return (
    <Screen title={t('v2.overview.title', 'Overview')} hero={hero} action={<SyncButton onSync={onSyncAll} />}>
      {data.reviewCount > 0 && (
        <div className="v2-gutter">
          <Link href={`${V2_BASE}/review` as never} className="block">
            <Card className="flex items-center gap-3 p-3.5">
              <span className="v2-bubble bg-[var(--v2-neg-soft)] text-[var(--v2-neg)]">
                <Inbox className="h-4 w-4" />
              </span>
              <span className="flex min-w-0 flex-1 flex-col">
                <span className="v2-title">
                  {t('v2.overview.reviewPending', { count: data.reviewCount }, '{count} to review')}
                </span>
                <span className="v2-sub truncate">
                  {t('v2.overview.reviewPendingHint', 'Some transactions are waiting for a category')}
                </span>
              </span>
              <ArrowUpRight className="h-4 w-4 flex-none text-[var(--v2-text-3)]" />
            </Card>
          </Link>
        </div>
      )}

      {/*
        * Two KPI tiles: the numbers that answer "can I spend today?".
        * Both are links — a figure that raises a question should lead to the
        * screen that answers it, and a card that looks tappable but isn't is
        * worse than one that plainly isn't.
        */}
      <div className="v2-gutter grid grid-cols-2 gap-3">
        <Link href={`${V2_BASE}/plan` as never} className="block">
        <Card className="flex h-full flex-col gap-1 p-4 transition-transform active:scale-[0.98]">
          <span className="v2-eyebrow">{t('v2.overview.leftToSpend', 'Left to spend')}</span>
          <Amount
            value={lts.leftToSpend}
            decimals={false}
            tone={lts.leftToSpend >= 0 ? 'neutral' : 'negative'}
            className="text-[26px] font-light leading-tight"
          />
          <span className="v2-micro leading-snug">
            {lts.dailyBudgetRemaining !== null
              ? `${m.fmt(lts.dailyBudgetRemaining, { decimals: false })}${t('v2.common.perDay', '/day')} · ${t('v2.overview.daysLeft', { count: lts.daysRemaining }, '{count} days left')}`
              : t('v2.overview.leftToSpendNone', 'No salary detected in the last 90 days')}
          </span>
        </Card>
        </Link>

        <Link
          href={
            {
              pathname: `${V2_BASE}/transactions`,
              query: { direction: 'expense', from: monthStart },
            } as never
          }
          className="block"
        >
        <Card className="flex h-full flex-col gap-1 p-4 transition-transform active:scale-[0.98]">
          <span className="v2-eyebrow">{t('v2.overview.spent', 'Spent')}</span>
          <Amount
            value={data.burnThisMonth}
            decimals={false}
            className="text-[26px] font-light leading-tight"
          />
          <span className="v2-micro leading-snug">
            {t('v2.overview.spentAvg', { amount: m.fmt(data.burnAvg6, { decimals: false }) }, '6-mo avg {amount}')}
          </span>
        </Card>
        </Link>
      </div>

      {/* Month forecast — a single bar reads faster than three numbers. */}
      <Section title={t('v2.overview.forecast', 'Month end')}>
        <div className="v2-gutter">
          <Link href={`${V2_BASE}/plan` as never} className="block">
          <Card className="flex flex-col gap-3 p-4 transition-transform active:scale-[0.99]">
            <div className="flex items-end justify-between gap-3">
              <div className="flex flex-col gap-0.5">
                <span className="v2-sub">{t('v2.overview.forecastMargin', 'Projected margin')}</span>
                {forecast.projectedMargin !== null ? (
                  <Amount
                    value={forecast.projectedMargin}
                    signed
                    decimals={false}
                    tone="auto"
                    className="text-[24px] font-light leading-tight"
                  />
                ) : (
                  <span className="v2-sub">—</span>
                )}
              </div>
              <span className="v2-micro text-right">
                {t('v2.overview.daysLeft', { count: forecast.daysRemaining }, '{count} days left')}
              </span>
            </div>

            <Track
              pct={
                forecast.monthIncome > 0
                  ? (forecast.projectedSpend / forecast.monthIncome) * 100
                  : 100
              }
              color={forecast.onTrack === false ? 'var(--v2-neg)' : 'var(--v2-accent)'}
            />

            <div className="flex items-center justify-between">
              <span className="v2-micro">
                <Amount value={forecast.projectedSpend} decimals={false} tone="muted" />
                {' / '}
                <Amount value={forecast.monthIncome} decimals={false} tone="muted" />
              </span>
              {forecast.fixedSpent > 0 && (
                <span className="v2-micro">
                  {t(
                    'v2.overview.forecastFixed',
                    { amount: m.fmt(forecast.fixedSpent, { decimals: false }) },
                    'including {amount} of fixed costs',
                  )}
                </span>
              )}
            </div>

            {data.incomeIsEstimated && (
              <p className="v2-micro text-[var(--v2-warn)]">
                {t(
                  'v2.overview.incomeEstimated',
                  'Salaire du mois pas encore reçu — basé sur le précédent',
                )}
              </p>
            )}
          </Card>
          </Link>
        </div>
      </Section>

      {/* Accounts. A horizontal carousel would look neat and hide half of them;
          six rows on one screen is what a net-worth app actually needs. */}
      <Section
        title={t('v2.overview.yourAccounts', 'Your accounts')}
        action={
          <Link href={`${V2_BASE}/accounts` as never} className="v2-micro text-[var(--v2-accent-text)]">
            {t('v2.common.seeAll', 'See all')}
          </Link>
        }
      >
        <div className="v2-gutter">
          <RowGroup>
            {data.accounts.slice(0, 6).map((a) => (
              <AccountRow key={a.id} account={a} href={`${V2_BASE}/accounts/${a.id}`} />
            ))}
          </RowGroup>
        </div>
      </Section>

      <Section
        title={t('v2.overview.recent', 'Recent activity')}
        action={
          <Link
            href={`${V2_BASE}/transactions` as never}
            className="v2-micro text-[var(--v2-accent-text)]"
          >
            {t('v2.common.seeAll', 'See all')}
          </Link>
        }
      >
        <div className="v2-gutter">
          <RowGroup>
            {data.recent.length === 0 ? (
              <Empty title={t('v2.activity.empty', 'No transactions')} />
            ) : (
              data.recent.map((tx) => (
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

      <AllocationCard allocation={data.allocation} />

      <SavingsCard rates={data.savings} />

      {data.goal && data.goal.target > 0 && <GoalCard goal={data.goal} />}

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

// ------------------------------------------------------------------ pieces

function SyncButton({ onSync }: { onSync?: () => Promise<unknown> }) {
  const t = useV2T()
  const router = useRouter()
  const [pending, start] = useTransition()
  if (!onSync) return null
  return (
    <button
      type="button"
      aria-label={t('v2.add.sync', 'Sync banks')}
      disabled={pending}
      onClick={() =>
        start(async () => {
          await onSync()
          router.refresh()
        })
      }
      className="v2-iconbtn"
    >
      <RefreshCw className={cn('h-[17px] w-[17px]', pending && 'animate-spin')} />
    </button>
  )
}

function AllocationCard({ allocation }: { allocation: NetWorthAllocation }) {
  const t = useV2T()
  const m = useMoney()
  const slices = [
    { key: 'cash', label: t('v2.overview.cash', 'Cash'), value: allocation.cash, color: 'var(--v2-s1)' },
    {
      key: 'invested',
      label: t('v2.overview.invested', 'Invested'),
      value: allocation.invested,
      color: 'var(--v2-s3)',
    },
  ]
  const total = slices.reduce((s, x) => s + x.value, 0)
  if (total <= 0) return null

  return (
    <Section title={t('v2.overview.allocation', 'Allocation')}>
      <div className="v2-gutter">
        <Card className="flex flex-col items-center gap-4 p-4">
          <Donut
            slices={slices}
            size={140}
            centerValue={m.compact(total)}
            centerLabel={t('v2.overview.gross', 'Gross')}
          />
          <DonutLegend
            className="w-full"
            slices={slices}
            total={total}
            format={(v) => m.fmt(v, { decimals: false })}
          />
        </Card>
      </div>
    </Section>
  )
}

function SavingsCard({ rates }: { rates: SavingsRates }) {
  const t = useV2T()
  const m = useMoney()
  const items = [
    { key: '3', label: '3', value: rates.threeMonth },
    { key: '6', label: '6', value: rates.sixMonth },
    { key: '12', label: '12', value: rates.twelveMonth },
  ]
  return (
    <Section title={t('v2.overview.savingsRate', 'Savings rate')}>
      <div className="v2-gutter">
        <Card className="flex flex-col gap-3 p-4">
          <div className="grid grid-cols-3 gap-3">
            {items.map((i) => (
              <div key={i.key} className="flex flex-col items-center gap-1">
                <span
                  className={cn(
                    'v2-num text-[22px] font-light leading-none',
                    i.value === null
                      ? 'text-[var(--v2-text-3)]'
                      : i.value >= 0
                        ? 'text-[var(--v2-pos)]'
                        : 'text-[var(--v2-neg)]',
                  )}
                >
                  {i.value === null ? '—' : m.pct(i.value, 0)}
                </span>
                <span className="v2-micro">
                  {i.label} {t('v2.common.months', 'months')}
                </span>
              </div>
            ))}
          </div>
          <p className="v2-micro text-center">
            {t('v2.overview.savingsRateHint', 'Saved ÷ income, over complete months')}
          </p>
        </Card>
      </div>
    </Section>
  )
}

function GoalCard({ goal }: { goal: GoalProjection }) {
  const t = useV2T()
  const m = useMoney()
  const { tag } = useV2Config()
  const pct = goal.target > 0 ? (goal.currentValue / goal.target) * 100 : 0
  const reach = goal.reachDateIso
    ? new Intl.DateTimeFormat(tag, { month: 'long', year: 'numeric' }).format(
        new Date(goal.reachDateIso),
      )
    : null

  return (
    <Section title={t('v2.overview.goal', 'Goal')}>
      <div className="v2-gutter">
        <Card className="flex flex-col gap-3 p-4">
          <div className="flex items-center gap-3">
            <span className="v2-bubble bg-[var(--v2-accent-soft)] text-[var(--v2-accent-text)]">
              <Target className="h-4 w-4" />
            </span>
            <span className="flex min-w-0 flex-1 flex-col">
              <span className="v2-title">
                <Amount value={goal.currentValue} decimals={false} />{' '}
                <span className="font-normal text-[var(--v2-text-3)]">
                  {t('v2.common.of', 'of')} {m.fmt(goal.target, { decimals: false })}
                </span>
              </span>
              <span className="v2-sub">
                {reach
                  ? t('v2.overview.goalReach', { date: reach }, 'Reached around {date}')
                  : t('v2.overview.goalNever', 'Out of reach at this pace')}
              </span>
            </span>
            <span className="v2-num text-[15px] font-medium">
            {pct < 10 ? pct.toFixed(1).replace('.', ',') : Math.round(pct)}%
          </span>
          </div>
          <Track pct={pct} color={seriesVar('goal')} />
          {/*
            * These two are the projected split of the TARGET at the reach date,
            * not money already moved: of the 100 000 €, this much will come
            * from deposits and this much from the market. Labelled "Versé" and
            * "Marché" they read as past tense, which is why the card looked
            * like it was claiming 67 000 € already contributed.
            */}
          <p className="v2-micro">
            {t(
              'v2.overview.goalSplit',
              {
                you: m.fmt(goal.contributed, { decimals: false }),
                market: m.fmt(goal.marketGrowth, { decimals: false }),
              },
              'At arrival: {you} from you, {market} from the market',
            )}
          </p>
        </Card>
      </div>
    </Section>
  )
}
