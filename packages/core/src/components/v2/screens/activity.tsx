'use client'

import { useEffect, useMemo, useState, useTransition } from 'react'
import {
  ChevronLeft,
  ChevronRight,
  CircleAlert,
  ListFilter,
  Search,
  Tags,
  Trash2,
} from 'lucide-react'
import { usePathname, useRouter, useSearchParams } from 'next/navigation'
import { useV2T } from '../i18n/context'
import { useV2Config } from '../lib/config'
import { dayLabel, isoDay } from '../lib/format'
import { Amount } from '../primitives/amount'
import { Empty } from '../primitives/atoms'
import { RowGroup } from '../primitives/row'
import { Segmented } from '../primitives/segmented'
import { Sheet } from '../primitives/sheet'
import { SwipeRow } from '../primitives/swipe-row'
import { Screen } from '../shell/screen'
import { CategoryPickerSheet } from './parts/category-picker-sheet'
import { TxDetailSheet, type TxDetailActions } from './parts/tx-detail-sheet'
import { TxRow } from './parts/tx-row'
import type { V2Account, V2Category, V2Tx } from '../types'
import { cn } from '../../../lib/utils'

export interface ActivityFilters {
  q: string
  accountId: string
  categoryId: string
  direction: 'all' | 'expense' | 'income'
  excludeTransfers: boolean
  needsReview: boolean
  from: string
  to: string
  page: number
}

export interface ActivityData {
  transactions: V2Tx[]
  total: number
  pageSize: number
  filters: ActivityFilters
  accounts: V2Account[]
  categories: V2Category[]
  /** Total awaiting review, independent of the current filters. */
  reviewCount: number
}

export type ActivityActions = TxDetailActions

function countActive(f: ActivityFilters): number {
  let n = 0
  if (f.q) n++
  if (f.accountId) n++
  if (f.categoryId) n++
  if (f.direction !== 'all') n++
  if (f.excludeTransfers) n++
  if (f.needsReview) n++
  if (f.from || f.to) n++
  return n
}

export function ActivityScreen({
  data,
  actions,
}: {
  data: ActivityData
  actions: ActivityActions
}) {
  const t = useV2T()
  const { tag } = useV2Config()
  const router = useRouter()
  const pathname = usePathname() ?? '/m/transactions'
  const params = useSearchParams()

  const [pending, startNavigation] = useTransition()
  /*
   * Optimistic filter state.
   *
   * Every filter change is a server round trip — the list is paginated and
   * filtered in SQL. Waiting for it before moving the chip makes the control
   * feel broken on a phone, so the chip flips immediately and the list catches
   * up behind a dimmed, still-scrollable view.
   */
  const [optimistic, setOptimistic] = useState<Partial<ActivityFilters> | null>(null)
  const filters = { ...data.filters, ...(optimistic ?? {}) }

  const [filtersOpen, setFiltersOpen] = useState(false)
  const [detail, setDetail] = useState<V2Tx | null>(null)
  const [picking, setPicking] = useState<V2Tx | null>(null)

  const active = countActive(filters)

  // Once the server's answer arrives, stop overlaying the guess on top of it.
  useEffect(() => {
    setOptimistic(null)
  }, [data.filters])
  const pages = Math.max(1, Math.ceil(data.total / data.pageSize))

  // Day buckets. The list arrives newest-first from the query layer, so a plain
  // sequential walk preserves order without a second sort.
  const days = useMemo(() => {
    const out: Array<{ key: string; label: string; items: V2Tx[]; net: number }> = []
    for (const tx of data.transactions) {
      const d = new Date(tx.date)
      const key = isoDay(d)
      const last = out[out.length - 1]
      if (last && last.key === key) {
        last.items.push(tx)
        last.net += tx.amount
      } else {
        out.push({
          key,
          label: dayLabel(d, tag, {
            today: t('v2.common.today', 'Today'),
            yesterday: t('v2.common.yesterday', 'Yesterday'),
          }),
          items: [tx],
          net: tx.amount,
        })
      }
    }
    return out
  }, [data.transactions, tag, t])

  const push = (next: Partial<ActivityFilters>, opts?: { scroll?: boolean }) => {
    setOptimistic((prev) => ({ ...(prev ?? {}), ...next }))
    const sp = new URLSearchParams(params?.toString() ?? '')
    const set = (k: string, v: string | number | boolean | undefined) => {
      if (v === undefined || v === '' || v === false || v === 0 || v === 'all') sp.delete(k)
      else sp.set(k, String(v))
    }
    if ('q' in next) set('q', next.q)
    if ('accountId' in next) set('accountId', next.accountId)
    if ('categoryId' in next) set('categoryId', next.categoryId)
    if ('direction' in next) set('direction', next.direction)
    if ('excludeTransfers' in next) set('excludeTransfers', next.excludeTransfers ? '1' : '')
    if ('needsReview' in next) set('needsReview', next.needsReview ? '1' : '')
    if ('from' in next) set('from', next.from)
    if ('to' in next) set('to', next.to)
    // Any filter change invalidates the page cursor — staying on page 4 of a
    // freshly narrowed result set is how you end up staring at an empty list.
    if ('page' in next) set('page', next.page === 1 ? '' : next.page)
    else sp.delete('page')
    // `scroll: false` keeps the reading position when narrowing a list; only a
    // page change should throw you back to the top.
    startNavigation(() => {
      router.push(`${pathname}?${sp.toString()}` as never, { scroll: opts?.scroll ?? false })
    })
  }

  const hero = (
    <div className="v2-gutter flex flex-col gap-2.5 pb-1">
      <h2 className="text-[30px] font-semibold leading-tight tracking-[-0.035em]">
        {t('v2.activity.title', 'Activity')}
      </h2>
      <SearchBox value={filters.q} onSubmit={(q) => push({ q })} />
      <div className="flex items-center gap-2">
        <button
          type="button"
          onClick={() => setFiltersOpen(true)}
          className={cn('v2-pill', active > 0 && 'v2-pill-accent')}
        >
          <ListFilter className="h-3.5 w-3.5" />
          {active > 0
            ? t('v2.activity.filtersActive', { count: active }, '{count} filters')
            : t('v2.activity.filters', 'Filters')}
        </button>
        {/*
          * Only rendered when the queue is non-empty. A permanent "0 à
          * vérifier" chip is noise; one that appears exactly when there is
          * work, carries the count, and toggles the filter on tap is the whole
          * feature in one control.
          */}
        {data.reviewCount > 0 && (
          <button
            type="button"
            onClick={() => push({ needsReview: !filters.needsReview })}
            aria-pressed={filters.needsReview}
            className={cn(
              'v2-pill transition-transform active:scale-95',
              filters.needsReview ? 'v2-pill-review-on' : 'v2-pill-warn',
            )}
          >
            <CircleAlert className="h-3.5 w-3.5" />
            {t(
              'v2.overview.reviewPending',
              { count: data.reviewCount },
              '{count} to review',
            )}
          </button>
        )}
        <span className="v2-micro">
          {t('v2.activity.count', { count: data.total }, '{count} transactions')}
        </span>
      </div>
    </div>
  )

  return (
    <Screen title={t('v2.activity.title', 'Activity')} hero={hero}>
      {days.length === 0 ? (
        <Empty
          title={t('v2.activity.empty', 'No transactions')}
          hint={t('v2.activity.emptyHint', 'Change the filters or sync your accounts.')}
          action={
            active > 0 ? (
              <button
                type="button"
                onClick={() =>
                  push({
                    q: '',
                    accountId: '',
                    categoryId: '',
                    direction: 'all',
                    excludeTransfers: false,
                    needsReview: false,
                    from: '',
                    to: '',
                  })
                }
                className="v2-btn v2-btn-soft"
              >
                {t('v2.common.reset', 'Reset')}
              </button>
            ) : undefined
          }
        />
      ) : (
        <div
          className={cn(
            'flex flex-col transition-opacity duration-150',
            pending && 'opacity-55',
          )}
        >
          {days.map((day) => (
            <section key={day.key}>
              <div className="v2-daybar flex items-center justify-between">
                <span>{day.label}</span>
                <Amount value={day.net} signed decimals={false} tone="muted" />
              </div>
              <div className="v2-gutter pb-4">
                <RowGroup>
                  {day.items.map((tx) => (
                    <SwipeRow
                      key={tx.id}
                      actions={[
                        {
                          key: 'cat',
                          label: t('v2.activity.categorize', 'Categorize'),
                          icon: <Tags className="h-4 w-4" />,
                          background: 'var(--v2-accent)',
                          onSelect: () => setPicking(tx),
                        },
                        {
                          key: 'del',
                          label: t('v2.common.delete', 'Delete'),
                          icon: <Trash2 className="h-4 w-4" />,
                          background: 'var(--v2-neg)',
                          onSelect: async () => {
                            await actions.softDeleteTransaction(tx.id)
                            router.refresh()
                          },
                        },
                      ]}
                    >
                      <TxRow
                        tx={tx}
                        secondary={tx.accountName}
                        onClick={() => setDetail(tx)}
                        className={tx.needsReview ? 'v2-row-review' : undefined}
                      />
                    </SwipeRow>
                  ))}
                </RowGroup>
              </div>
            </section>
          ))}
        </div>
      )}

      {pages > 1 && (
        <div className="v2-gutter flex items-center justify-between gap-3">
          <button
            type="button"
            disabled={filters.page <= 1 || pending}
            onClick={() => push({ page: filters.page - 1 }, { scroll: true })}
            className="v2-btn v2-btn-soft flex-1"
          >
            <ChevronLeft className="h-4 w-4" />
          </button>
          <span className="v2-num v2-micro">
            {filters.page} / {pages}
          </span>
          <button
            type="button"
            disabled={filters.page >= pages || pending}
            onClick={() => push({ page: filters.page + 1 }, { scroll: true })}
            className="v2-btn v2-btn-soft flex-1"
          >
            <ChevronRight className="h-4 w-4" />
          </button>
        </div>
      )}

      <FiltersSheet
        open={filtersOpen}
        onClose={() => setFiltersOpen(false)}
        filters={filters}
        accounts={data.accounts}
        categories={data.categories}
        onApply={(next) => {
          setFiltersOpen(false)
          push(next)
        }}
      />

      <TxDetailSheet
        tx={detail}
        onClose={() => setDetail(null)}
        onCategorize={() => {
          const tx = detail
          setDetail(null)
          setPicking(tx)
        }}
        actions={actions}
      />

      <CategoryPickerSheet
        open={picking !== null}
        onClose={() => setPicking(null)}
        categories={data.categories}
        currentId={picking?.categoryId ?? null}
        onPick={async (categoryId) => {
          if (picking) await actions.updateTransactionCategory(picking.id, categoryId)
        }}
      />
    </Screen>
  )
}

// ------------------------------------------------------------------ search

function SearchBox({ value, onSubmit }: { value: string; onSubmit: (v: string) => void }) {
  const t = useV2T()
  const [draft, setDraft] = useState(value)
  return (
    <form
      onSubmit={(e) => {
        e.preventDefault()
        onSubmit(draft)
      }}
      className="relative"
    >
      <Search
        aria-hidden
        className="pointer-events-none absolute left-3.5 top-1/2 h-4 w-4 -translate-y-1/2 text-[var(--v2-text-3)]"
      />
      <input
        value={draft}
        onChange={(e) => setDraft(e.target.value)}
        type="search"
        enterKeyHint="search"
        placeholder={t('v2.activity.searchPlaceholder', 'Payee, note…')}
        aria-label={t('v2.common.search', 'Search')}
        className="v2-input pl-10"
      />
    </form>
  )
}

// ----------------------------------------------------------------- filters

function FiltersSheet({
  open,
  onClose,
  filters,
  accounts,
  categories,
  onApply,
}: {
  open: boolean
  onClose: () => void
  filters: ActivityFilters
  accounts: V2Account[]
  categories: V2Category[]
  onApply: (next: Partial<ActivityFilters>) => void
}) {
  const t = useV2T()
  const [draft, setDraft] = useState(filters)

  // Re-seed whenever the sheet opens so it always reflects the live URL.
  const [seenOpen, setSeenOpen] = useState(false)
  if (open && !seenOpen) {
    setSeenOpen(true)
    setDraft(filters)
  }
  if (!open && seenOpen) setSeenOpen(false)

  return (
    <Sheet open={open} onClose={onClose} title={t('v2.activity.filters', 'Filters')}>
      <div className="v2-gutter flex flex-col gap-4 pt-1">
        <div className="flex flex-col gap-1.5">
          <span className="v2-eyebrow">{t('v2.activity.direction', 'Direction')}</span>
          <Segmented
            value={draft.direction}
            onChange={(direction) => setDraft({ ...draft, direction })}
            options={[
              { value: 'all', label: t('v2.common.all', 'All') },
              { value: 'expense', label: t('v2.activity.expenses', 'Expenses') },
              { value: 'income', label: t('v2.activity.income', 'Income') },
            ]}
          />
        </div>

        <label className="flex flex-col gap-1.5">
          <span className="v2-eyebrow">{t('v2.add.account', 'Account')}</span>
          <select
            value={draft.accountId}
            onChange={(e) => setDraft({ ...draft, accountId: e.target.value })}
            className="v2-input"
          >
            <option value="">{t('v2.common.all', 'All')}</option>
            {accounts.map((a) => (
              <option key={a.id} value={a.id}>
                {a.name}
              </option>
            ))}
          </select>
        </label>

        <label className="flex flex-col gap-1.5">
          <span className="v2-eyebrow">{t('v2.add.category', 'Category')}</span>
          <select
            value={draft.categoryId}
            onChange={(e) => setDraft({ ...draft, categoryId: e.target.value })}
            className="v2-input"
          >
            <option value="">{t('v2.common.all', 'All')}</option>
            <option value="none">{t('v2.common.uncategorized', 'Uncategorized')}</option>
            {categories.map((c) => (
              <option key={c.id} value={c.id}>
                {c.emoji ? `${c.emoji} ` : ''}
                {c.name}
              </option>
            ))}
          </select>
        </label>

        <div className="grid grid-cols-2 gap-3">
          <label className="flex flex-col gap-1.5">
            <span className="v2-eyebrow">{t('v2.activity.period', 'Period')}</span>
            <input
              type="date"
              value={draft.from}
              onChange={(e) => setDraft({ ...draft, from: e.target.value })}
              className="v2-input"
            />
          </label>
          <label className="flex flex-col gap-1.5">
            <span className="v2-eyebrow">&nbsp;</span>
            <input
              type="date"
              value={draft.to}
              onChange={(e) => setDraft({ ...draft, to: e.target.value })}
              className="v2-input"
            />
          </label>
        </div>

        <button
          type="button"
          onClick={() => setDraft({ ...draft, excludeTransfers: !draft.excludeTransfers })}
          className="flex items-center justify-between gap-3 py-1"
        >
          <span className="v2-title">
            {t('v2.activity.excludeTransfers', 'Hide transfers')}
          </span>
          <span
            aria-hidden
            className={cn(
              'flex h-[26px] w-[44px] items-center rounded-full p-[3px] transition-colors',
              draft.excludeTransfers ? 'bg-[var(--v2-accent)]' : 'bg-[var(--v2-surface-3)]',
            )}
          >
            <span
              className="h-5 w-5 rounded-full bg-white shadow transition-transform"
              style={{ transform: draft.excludeTransfers ? 'translateX(18px)' : 'translateX(0)' }}
            />
          </span>
        </button>

        <div className="flex gap-3 pt-1">
          <button
            type="button"
            onClick={() =>
              onApply({
                q: '',
                accountId: '',
                categoryId: '',
                direction: 'all',
                excludeTransfers: false,
                needsReview: false,
                from: '',
                to: '',
              })
            }
            className="v2-btn v2-btn-soft flex-1"
          >
            {t('v2.common.reset', 'Reset')}
          </button>
          <button
            type="button"
            onClick={() => onApply(draft)}
            className="v2-btn v2-btn-primary flex-1"
          >
            {t('v2.common.apply', 'Apply')}
          </button>
        </div>
      </div>
    </Sheet>
  )
}
