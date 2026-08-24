'use client'

import { useMemo, useState } from 'react'
import { useRouter } from 'next/navigation'
import { ChevronLeft, ChevronRight, Repeat, TrendingDown, TrendingUp } from 'lucide-react'
import type {
  CategoryShare,
  CategorySpendingSeries,
  DailySpend,
  MonthlyFlow,
  SavingsRates,
  SubscriptionMatch,
} from '../../../types'
import { useV2T } from '../i18n/context'
import { useMoney, useV2Config } from '../lib/config'
import { monthLabel, seriesVar } from '../lib/format'
import { Amount } from '../primitives/amount'
import { Card, Empty, Pill, Section } from '../primitives/atoms'
import { FlowBars, RankBars } from '../primitives/bars'
import { RowGroup } from '../primitives/row'
import { Segmented } from '../primitives/segmented'
import { Sparkline } from '../primitives/sparkline'
import { Screen } from '../shell/screen'
import { V2_BASE } from '../shell/nav'
import { cn } from '../../../lib/utils'

export interface AnalysisData {
  flows: MonthlyFlow[]
  categories: CategoryShare[]
  /**
   * `groupName/categoryName` → category id, so a bar can link to its filtered
   * transactions. `getCategoryBreakdown` does not return ids and it is shared
   * with the shipping UI, so the map is built in the page adapter from
   * `listCategoriesByGroup` rather than by widening a query the v1 screens
   * also depend on. A row whose key is missing simply is not a link.
   */
  categoryIds?: Record<string, string>
  categorySeries: CategorySpendingSeries
  dailySpend: DailySpend[]
  subscriptions: SubscriptionMatch[]
  savings: SavingsRates
  ageOfMoney: number | null
}

type Tab = 'overview' | 'trends' | 'flows' | 'heatmap' | 'subs'

export function AnalysisScreen({ data }: { data: AnalysisData }) {
  const t = useV2T()
  const [tab, setTab] = useState<Tab>('overview')

  const hero = (
    <div className="flex flex-col gap-3 pb-1">
      <h2 className="v2-gutter text-[30px] font-semibold leading-tight tracking-[-0.035em]">
        {t('v2.analysis.title', 'Analysis')}
      </h2>
      <div className="v2-gutter">
        <Segmented
          scrollable
          value={tab}
          onChange={setTab}
          options={[
            { value: 'overview', label: t('v2.analysis.tab.overview', 'Overview') },
            { value: 'trends', label: t('v2.analysis.tab.trends', 'Trends') },
            { value: 'flows', label: t('v2.analysis.tab.flows', 'Flows') },
            { value: 'heatmap', label: t('v2.analysis.tab.heatmap', 'Calendar') },
            { value: 'subs', label: t('v2.analysis.tab.subs', 'Subscriptions') },
          ]}
        />
      </div>
    </div>
  )

  return (
    <Screen title={t('v2.analysis.title', 'Analysis')} hero={hero}>
      {tab === 'overview' && <OverviewTab data={data} />}
      {tab === 'trends' && <TrendsTab series={data.categorySeries} />}
      {tab === 'flows' && <FlowsTab flows={data.flows} />}
      {tab === 'heatmap' && <HeatmapTab days={data.dailySpend} />}
      {tab === 'subs' && <SubsTab subscriptions={data.subscriptions} />}
    </Screen>
  )
}

// ---------------------------------------------------------------- overview

function OverviewTab({ data }: { data: AnalysisData }) {
  const t = useV2T()
  const m = useMoney()
  const { tag } = useV2Config()
  const router = useRouter()

  const bars = useMemo(
    () =>
      data.flows.map((f) => ({
        key: f.month,
        label: monthLabel(f.month, tag),
        income: f.income,
        expense: f.expense,
        net: f.net,
      })),
    [data.flows, tag],
  )

  const [picked, setPicked] = useState<string | null>(null)
  const active = bars.find((b) => b.key === picked) ?? bars[bars.length - 1]

  const top = data.categories.slice(0, 8)

  return (
    <>
      <Section title={t('v2.overview.savingsRate', 'Savings rate')}>
        <div className="v2-gutter grid grid-cols-3 gap-3">
          {(
            [
              ['3', data.savings.threeMonth],
              ['6', data.savings.sixMonth],
              ['12', data.savings.twelveMonth],
            ] as const
          ).map(([label, value]) => (
            <Card key={label} className="flex flex-col items-center gap-1 p-3.5">
              <span
                className={cn(
                  'v2-num text-[21px] font-light leading-none',
                  value === null
                    ? 'text-[var(--v2-text-3)]'
                    : value >= 0
                      ? 'text-[var(--v2-pos)]'
                      : 'text-[var(--v2-neg)]',
                )}
              >
                {value === null ? '—' : m.pct(value, 0)}
              </span>
              <span className="v2-micro">
                {label} {t('v2.common.months', 'months')}
              </span>
            </Card>
          ))}
        </div>
      </Section>

      <Section
        title={`${t('v2.analysis.income', 'Income')} · ${t('v2.analysis.expense', 'Spending')}`}
        action={
          active ? (
            <span className="v2-micro">
              {monthLabel(active.key, tag, true)} ·{' '}
              <Amount value={active.net} signed decimals={false} tone="auto" />
            </span>
          ) : undefined
        }
      >
        <div className="v2-gutter">
          <Card className="p-4">
            <FlowBars
              data={bars}
              selected={picked}
              onSelect={(d) => setPicked(d?.key ?? null)}
              describe={(d) =>
                `${monthLabel(d.key, tag, true)} · ${t('v2.analysis.income', 'Income')} ${m.fmt(
                  d.income,
                  { decimals: false },
                )} · ${t('v2.analysis.expense', 'Spending')} ${m.fmt(d.expense, { decimals: false })}`
              }
            />
          </Card>
        </div>
      </Section>

      {data.ageOfMoney !== null && (
        <div className="v2-gutter">
          <Card className="flex items-center gap-3 p-4">
            <span className="flex flex-none items-baseline gap-1">
              <span className="v2-num text-[28px] font-light leading-none">
                {Math.round(data.ageOfMoney)}
              </span>
              <span className="v2-micro">{t('v2.common.days', 'days')}</span>
            </span>
            <span className="flex min-w-0 flex-col">
              <span className="v2-title">{t('v2.analysis.ageOfMoney', 'Age of money')}</span>
              <span className="v2-sub">
                {t(
                  'v2.analysis.ageOfMoneyHint',
                  'How long the money you spend has been with you',
                )}
              </span>
            </span>
          </Card>
        </div>
      )}

      <Section title={t('v2.analysis.byCategory', 'By category')}>
        <div className="v2-gutter">
          <Card flush className="py-1">
            {top.length === 0 ? (
              <Empty title={t('v2.analysis.noSpend', 'No spending')} />
            ) : (
              <RankBars
                items={top.map((c) => ({
                  key: `${c.groupName}/${c.categoryName}`,
                  label: c.categoryName,
                  emoji: c.emoji,
                  value: c.total,
                  color: seriesVar(c.categoryName),
                }))}
                format={(v) => m.fmt(v, { decimals: false })}
                onSelect={(item) => {
                  const id = data.categoryIds?.[item.key]
                  if (!id) return
                  router.push(
                    `${V2_BASE}/transactions?categoryId=${encodeURIComponent(id)}&direction=expense` as never,
                  )
                }}
              />
            )}
          </Card>
        </div>
      </Section>
    </>
  )
}

// ------------------------------------------------------------------ trends

function TrendsTab({ series }: { series: CategorySpendingSeries }) {
  const t = useV2T()
  const m = useMoney()
  const { tag } = useV2Config()

  const rows = series.categories.slice(0, 8)

  if (rows.length === 0) {
    return <Empty title={t('v2.analysis.noSpend', 'No spending')} />
  }

  return (
    <div className="v2-gutter flex flex-col gap-3">
      {rows.map((c) => {
        // Compare the latest complete pair of halves rather than last month vs
        // the one before: a single month is far too noisy to call a "trend".
        const half = Math.floor(c.monthly.length / 2)
        const older = c.monthly.slice(0, half)
        const recent = c.monthly.slice(half)
        const avg = (xs: number[]) => (xs.length ? xs.reduce((s, x) => s + x, 0) / xs.length : 0)
        const before = avg(older)
        const after = avg(recent)
        const deltaPct = before > 0 ? ((after - before) / before) * 100 : null
        const rising = deltaPct !== null && deltaPct > 5
        const falling = deltaPct !== null && deltaPct < -5

        return (
          <Card key={c.categoryId} className="flex flex-col gap-2 p-4">
            <div className="flex items-baseline gap-2">
              {c.emoji && <span className="text-[15px] leading-none">{c.emoji}</span>}
              <span className="v2-title min-w-0 flex-1 truncate">{c.categoryName}</span>
              <Amount value={c.total} decimals={false} className="text-[14px]" />
            </div>

            <Sparkline
              data={c.monthly.map((v, i) => ({
                x: i,
                y: v,
                label: series.months[i],
              }))}
              height={44}
              color={seriesVar(c.categoryName)}
              fill
            />

            <div className="flex items-center justify-between">
              <span className="v2-micro">
                {series.months.length > 0 &&
                  `${monthLabel(series.months[0]!, tag)} → ${monthLabel(
                    series.months[series.months.length - 1]!,
                    tag,
                  )}`}
              </span>
              {deltaPct !== null && (
                <Pill tone={rising ? 'negative' : falling ? 'positive' : 'neutral'}>
                  {rising ? (
                    <TrendingUp className="h-3 w-3" />
                  ) : falling ? (
                    <TrendingDown className="h-3 w-3" />
                  ) : null}
                  {m.pct(deltaPct, 0)}
                </Pill>
              )}
            </div>
          </Card>
        )
      })}
    </div>
  )
}

// ------------------------------------------------------------------- flows

function FlowsTab({ flows }: { flows: MonthlyFlow[] }) {
  const t = useV2T()
  const { tag } = useV2Config()
  const reversed = useMemo(() => [...flows].reverse(), [flows])

  /*
   * One scale for the whole table.
   *
   * Sizing each row against its own maximum is the trap: an in-progress month
   * with €1 013 of income then draws the same full-width bar as a €3 787 one,
   * and the table says every month is identical. The comparison only means
   * anything against a shared denominator.
   */
  const max = Math.max(1, ...flows.flatMap((f) => [f.income, f.expense]))

  if (flows.length === 0) return <Empty title={t('v2.analysis.noSpend', 'No spending')} />

  return (
    <div className="v2-gutter">
      <RowGroup>
        {reversed.map((f) => (
          <div key={f.month} className="v2-row items-start gap-3 py-3">
            <span className="v2-title w-[74px] flex-none truncate capitalize">
              {monthLabel(f.month, tag, true)}
            </span>

            <span className="flex min-w-0 flex-1 flex-col gap-1.5 pt-1">
              <i
                className="block h-[4px] rounded-full bg-[var(--v2-pos)]"
                style={{ width: `${Math.max(1.5, (f.income / max) * 100)}%` }}
              />
              <i
                className="block h-[4px] rounded-full bg-[var(--v2-neg)]"
                style={{ width: `${Math.max(1.5, (f.expense / max) * 100)}%` }}
              />
            </span>

            <span className="flex flex-none flex-col items-end">
              <Amount value={f.net} signed decimals={false} tone="auto" className="text-[14px]" />
              <span className="v2-micro">
                <Amount value={f.income} decimals={false} tone="muted" /> ·{' '}
                <Amount value={f.expense} decimals={false} tone="muted" />
              </span>
            </span>
          </div>
        ))}
      </RowGroup>
    </div>
  )
}

// ----------------------------------------------------------------- heatmap

/** Five buckets. A continuous ramp turns a year of spending into one flat wash. */
const HEAT_LEVELS = 5

/**
 * Spending calendar.
 *
 * This started as a GitHub-style year grid and that was the wrong form for a
 * phone: 53 columns need ~700px, so on a 390px screen half the year hid behind
 * a scroll, the cells were 11px — a quarter of the 44px minimum touch target —
 * and with no weekday labels the pattern read as noise. A month at a time fits
 * exactly seven columns of real, tappable cells, which is also how people
 * actually think about their spending.
 *
 * The colour scale is still computed over the whole window, not the visible
 * month, so a quiet month looks quiet instead of being re-normalised to look
 * just as busy as a heavy one.
 */
function HeatmapTab({ days }: { days: DailySpend[] }) {
  const t = useV2T()
  const m = useMoney()
  const { tag } = useV2Config()
  const [monthOffset, setMonthOffset] = useState(0)
  const [picked, setPicked] = useState<DailySpend | null>(null)

  const byDate = useMemo(() => new Map(days.map((d) => [d.date, d.amount])), [days])

  const thresholds = useMemo(() => {
    const spent = days.map((d) => d.amount).filter((a) => a > 0).sort((a, b) => a - b)
    const cuts: number[] = []
    for (let i = 1; i < HEAT_LEVELS; i++) {
      cuts.push(spent.length ? spent[Math.floor((spent.length * i) / HEAT_LEVELS)]! : 0)
    }
    return cuts
  }, [days])

  const earliest = useMemo(() => {
    const sorted = days.map((d) => d.date).sort()
    return sorted[0] ?? null
  }, [days])

  const today = new Date()
  const cursor = new Date(today.getFullYear(), today.getMonth() + monthOffset, 1)
  const monthName = new Intl.DateTimeFormat(tag, { month: 'long', year: 'numeric' }).format(cursor)

  /*
   * The weekday profile spans the whole window, not the visible month.
   * A single month gives four or five samples per weekday, so one heavy
   * Thursday becomes "you spend on Thursdays" — a statistic built from one
   * data point. Over a year it means something.
   */
  const weekdays = useMemo(() => {
    const sums = new Array(7).fill(0)
    const counts = new Array(7).fill(0)
    for (const d of days) {
      const idx = (new Date(`${d.date}T12:00:00`).getDay() + 6) % 7
      sums[idx] += d.amount
      counts[idx] += 1
    }
    return sums.map((sum, i) => (counts[i] ? sum / counts[i] : 0))
  }, [days])

  const { cells, monthTotal } = useMemo(() => {
    const year = cursor.getFullYear()
    const month = cursor.getMonth()
    const daysInMonth = new Date(year, month + 1, 0).getDate()
    // Monday-first: JS getDay() is Sunday-first, so rotate it.
    const leading = (new Date(year, month, 1).getDay() + 6) % 7

    const out: Array<DailySpend | null> = Array.from({ length: leading }, () => null)
    let total = 0

    for (let day = 1; day <= daysInMonth; day++) {
      const iso = `${year}-${String(month + 1).padStart(2, '0')}-${String(day).padStart(2, '0')}`
      const amount = byDate.get(iso) ?? 0
      out.push({ date: iso, amount })
      total += amount
    }
    return { cells: out, monthTotal: total }
  }, [cursor.getFullYear(), cursor.getMonth(), byDate])

  const levelOf = (amount: number): number => {
    if (amount <= 0) return 0
    let level = 1
    for (const cut of thresholds) if (amount > cut) level++
    return Math.min(HEAT_LEVELS, level)
  }

  const shade = (level: number): string =>
    level === 0
      ? 'var(--v2-surface-2)'
      : `color-mix(in oklab, var(--v2-accent) ${[0, 20, 39, 58, 78, 100][level]}%, var(--v2-surface-2))`

  // Monday-first initials straight from Intl, so this reads right in any locale.
  const weekdayLabels = Array.from({ length: 7 }, (_, i) =>
    new Intl.DateTimeFormat(tag, { weekday: 'narrow' }).format(new Date(2024, 0, 1 + i)),
  )

  const atEarliest = earliest !== null && cursor <= new Date(`${earliest.slice(0, 7)}-01T00:00:00`)

  return (
    <div className="flex flex-col gap-4">
      <div className="v2-gutter">
        <Card className="flex flex-col gap-3 p-4">
          <div className="flex items-center justify-between gap-2">
            <button
              type="button"
              onClick={() => {
                setMonthOffset((o) => o - 1)
                setPicked(null)
              }}
              disabled={atEarliest}
              aria-label={t('v2.plan.prevMonth', 'Mois précédent')}
              className="grid h-8 w-8 place-items-center rounded-full text-[var(--v2-text-2)] disabled:opacity-30"
            >
              <ChevronLeft className="h-4 w-4" />
            </button>
            <div className="flex flex-col items-center">
              <span className="v2-title capitalize">{monthName}</span>
              <Amount value={monthTotal} decimals={false} tone="muted" className="text-[12px]" />
            </div>
            <button
              type="button"
              onClick={() => {
                setMonthOffset((o) => o + 1)
                setPicked(null)
              }}
              disabled={monthOffset >= 0}
              aria-label={t('v2.plan.nextMonth', 'Mois suivant')}
              className="grid h-8 w-8 place-items-center rounded-full text-[var(--v2-text-2)] disabled:opacity-30"
            >
              <ChevronRight className="h-4 w-4" />
            </button>
          </div>

          <div className="grid grid-cols-7 gap-1.5">
            {weekdayLabels.map((label, i) => (
              <span
                key={`h${i}`}
                aria-hidden
                className="pb-0.5 text-center text-[10px] uppercase text-[var(--v2-text-3)]"
              >
                {label}
              </span>
            ))}

            {cells.map((cell, i) =>
              cell === null ? (
                <span key={`p${i}`} />
              ) : (
                <button
                  key={cell.date}
                  type="button"
                  onClick={() => setPicked(picked?.date === cell.date ? null : cell)}
                  aria-label={`${new Intl.DateTimeFormat(tag, { dateStyle: 'long' }).format(
                    new Date(`${cell.date}T12:00:00`),
                  )} — ${m.fmt(cell.amount, { decimals: false })}`}
                  aria-pressed={picked?.date === cell.date}
                  className={cn(
                    'flex aspect-square flex-col items-center justify-center rounded-[11px] transition-transform active:scale-95',
                    picked?.date === cell.date && 'ring-2 ring-[var(--v2-text)]',
                  )}
                  style={{ background: shade(levelOf(cell.amount)) }}
                >
                  <span
                    className={cn(
                      'v2-num text-[13px] leading-none',
                      levelOf(cell.amount) >= 4
                        ? 'font-medium text-[var(--v2-on-accent)]'
                        : 'text-[var(--v2-text-2)]',
                    )}
                  >
                    {Number(cell.date.slice(8))}
                  </span>
                </button>
              ),
            )}
          </div>

          <div className="flex min-h-[20px] items-center justify-between gap-3">
            {picked ? (
              <>
                <span className="v2-sub">
                  {new Intl.DateTimeFormat(tag, { dateStyle: 'long' }).format(
                    new Date(`${picked.date}T12:00:00`),
                  )}
                </span>
                <Amount value={picked.amount} decimals={false} />
              </>
            ) : (
              <>
                <span className="v2-micro">{t('v2.analysis.tapDay', 'Touche un jour')}</span>
                <span className="flex items-center gap-1">
                  <span className="v2-micro">{t('v2.common.less', 'Moins')}</span>
                  {Array.from({ length: HEAT_LEVELS + 1 }, (_, i) => (
                    <i
                      key={i}
                      aria-hidden
                      className="h-[9px] w-[9px] rounded-[2px]"
                      style={{ background: shade(i) }}
                    />
                  ))}
                  <span className="v2-micro">{t('v2.common.more', 'Plus')}</span>
                </span>
              </>
            )}
          </div>
        </Card>
      </div>

      <WeekdayProfile means={weekdays} />
    </div>
  )
}

/** Seven bars: the average spend for each day of the week. */
function WeekdayProfile({ means }: { means: number[] }) {
  const t = useV2T()
  const m = useMoney()
  const { tag } = useV2Config()
  const max = Math.max(1, ...means)
  const peak = means.indexOf(max)

  // Monday-first weekday initials straight from Intl, so this reads right in
  // every locale instead of a hardcoded "L M M J V S D".
  const labels = Array.from({ length: 7 }, (_, i) =>
    new Intl.DateTimeFormat(tag, { weekday: 'short' })
      .format(new Date(2024, 0, 1 + i))
      .replace('.', ''),
  )

  return (
    <Section title={t('v2.analysis.byWeekday', 'Par jour de semaine')}>
      <div className="v2-gutter">
        <Card className="flex items-end gap-2 p-4" style={{ height: 132 }}>
          {means.map((value, i) => (
            <div key={i} className="flex h-full min-w-0 flex-1 flex-col items-center gap-1.5">
              <span className="v2-num text-[9px] leading-none text-[var(--v2-text-3)]">
                {m.compact(value)}
              </span>
              <span className="flex w-full flex-1 items-end">
                <i
                  className="w-full rounded-t-[4px]"
                  style={{
                    height: `${Math.max(3, (value / max) * 100)}%`,
                    background: i === peak ? 'var(--v2-accent)' : 'var(--v2-surface-3)',
                  }}
                />
              </span>
              <span
                className={cn(
                  'text-[10px] leading-none',
                  i === peak ? 'text-[var(--v2-text)]' : 'text-[var(--v2-text-3)]',
                )}
              >
                {labels[i]}
              </span>
            </div>
          ))}
        </Card>
      </div>
    </Section>
  )
}

// ----------------------------------------------------------- subscriptions

function SubsTab({ subscriptions }: { subscriptions: SubscriptionMatch[] }) {
  const t = useV2T()
  const m = useMoney()
  const { tag } = useV2Config()

  if (subscriptions.length === 0) {
    return (
      <Empty
        icon={<Repeat className="h-5 w-5" />}
        title={t('v2.analysis.subsEmpty', 'No subscriptions detected')}
      />
    )
  }

  // Normalise every cadence to a month so weekly and yearly charges can be
  // added together honestly.
  const monthly = subscriptions.reduce(
    (s, x) => s + (Math.abs(x.amount) * 30.44) / Math.max(1, x.cadenceDays),
    0,
  )
  const annual = subscriptions.reduce((s, x) => s + x.annualCost, 0)

  return (
    <div className="flex flex-col gap-4">
      <div className="v2-gutter grid grid-cols-2 gap-3">
        <Card className="flex flex-col gap-1 p-4">
          <span className="v2-eyebrow">{t('v2.analysis.subsMonthly', 'Per month')}</span>
          <Amount
            value={monthly}
            decimals={false}
            className="text-[22px] font-light leading-tight"
          />
        </Card>
        <Card className="flex flex-col gap-1 p-4">
          <span className="v2-eyebrow">{t('v2.analysis.subsAnnual', 'Per year')}</span>
          <Amount
            value={annual}
            decimals={false}
            className="text-[22px] font-light leading-tight"
          />
        </Card>
      </div>

      <div className="v2-gutter">
        <p className="v2-micro pb-2">
          {t(
            'v2.analysis.subsCount',
            { count: subscriptions.length },
            '{count} subscriptions detected',
          )}
        </p>
        <RowGroup>
          {subscriptions.map((s) => (
            <div key={`${s.payee}-${s.amount}`} className="v2-row">
              <span className="v2-bubble">
                <Repeat className="h-4 w-4" />
              </span>
              <span className="flex min-w-0 flex-1 flex-col gap-0.5">
                <span className="v2-title truncate">{s.payee}</span>
                <span className="v2-sub truncate">
                  {t('v2.analysis.subsEvery', { days: s.cadenceDays }, 'every {days} days')}
                  {s.categoryName ? ` · ${s.categoryName}` : ''}
                </span>
              </span>
              <span className="flex flex-none flex-col items-end gap-0.5">
                <Amount value={Math.abs(s.amount)} className="text-[15px]" />
                <span className="v2-micro">
                  {t(
                    'v2.analysis.subsLast',
                    {
                      date: new Intl.DateTimeFormat(tag, {
                        day: 'numeric',
                        month: 'short',
                      }).format(new Date(s.lastSeen)),
                    },
                    'Last {date}',
                  )}
                </span>
              </span>
            </div>
          ))}
        </RowGroup>
      </div>
    </div>
  )
}
