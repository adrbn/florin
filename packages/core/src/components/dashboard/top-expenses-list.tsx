'use client'

import { useState, useTransition } from 'react'
import type { TopSpendMode, TopSpendResult } from '../../types'
import { Card, CardContent, CardHeader, CardTitle } from '../ui/card'
import { useT } from '../../i18n/context'
import { formatCurrency, parseDecimalInput } from '../../lib/format/currency'

interface CategoryOption {
  id: string
  name: string
  emoji: string | null
  groupName: string
}

export interface TopSpendFetchParams {
  mode: TopSpendMode
  days: number
  categoryId: string | null
  limit: number
  minAmount: number
}

export interface TopExpensesListProps {
  initial: TopSpendResult
  categories: ReadonlyArray<CategoryOption>
  defaultDays: number
  onFetchTopSpend: (params: TopSpendFetchParams) => Promise<TopSpendResult>
}

const DAY_OPTIONS = [7, 30, 60, 90, 180, 365] as const
const COUNT_OPTIONS = [5, 10, 20] as const

export function TopExpensesList({
  initial,
  categories,
  defaultDays,
  onFetchTopSpend,
}: TopExpensesListProps) {
  const t = useT()
  const [mode, setMode] = useState<TopSpendMode>('transactions')
  const [days, setDays] = useState<number>(defaultDays)
  const [categoryId, setCategoryId] = useState<string>('') // '' = all
  const [limit, setLimit] = useState<number>(5)
  // Min-amount kept as a string so clearing the box leaves it empty instead of
  // snapping to "0" — see parseDecimalInput.
  const [minDraft, setMinDraft] = useState<string>('')
  const [result, setResult] = useState<TopSpendResult>(initial)
  const [pending, startTransition] = useTransition()

  const refresh = (patch: Partial<TopSpendFetchParams>): void => {
    const params: TopSpendFetchParams = {
      mode,
      days,
      categoryId: categoryId === '' ? null : categoryId,
      limit,
      minAmount: parseDecimalInput(minDraft, 0),
      ...patch,
    }
    startTransition(async () => {
      setResult(await onFetchTopSpend(params))
    })
  }

  const items = result.items
  const modeButton = (m: TopSpendMode, label: string) => (
    <button
      type="button"
      onClick={() => {
        setMode(m)
        refresh({ mode: m })
      }}
      disabled={pending}
      className={`rounded px-2 py-0.5 text-[11px] font-medium transition-colors disabled:opacity-50 ${
        mode === m ? 'bg-foreground text-background' : 'text-muted-foreground hover:text-foreground'
      }`}
    >
      {label}
    </button>
  )

  return (
    <Card className="flex h-full flex-col">
      <CardHeader className="space-y-2 pb-2">
        <div className="flex items-center justify-between gap-2">
          <CardTitle className="text-base">{t('dashboard.topSpend', 'Top spending')}</CardTitle>
          <div className="flex shrink-0 items-center gap-0.5 rounded-md border border-border p-0.5">
            {modeButton('transactions', t('dashboard.modeTransactions', 'Transactions'))}
            {modeButton('merchants', t('dashboard.modeMerchants', 'Merchants'))}
          </div>
        </div>
        <div className="flex flex-wrap gap-2">
          <select
            value={days}
            onChange={(e) => {
              const next = Number(e.target.value)
              setDays(next)
              refresh({ days: next })
            }}
            disabled={pending}
            aria-label={t('dashboard.timeWindow', 'Time window')}
            className="h-7 rounded-md border border-input bg-transparent px-2 text-xs outline-none focus-visible:border-ring focus-visible:ring-2 focus-visible:ring-ring/40 disabled:opacity-50"
          >
            {DAY_OPTIONS.map((d) => (
              <option key={d} value={d}>
                {t('dashboard.lastNDays', { n: d }, `Last ${d} days`)}
              </option>
            ))}
          </select>
          <select
            value={categoryId}
            onChange={(e) => {
              const next = e.target.value
              setCategoryId(next)
              refresh({ categoryId: next === '' ? null : next })
            }}
            disabled={pending}
            aria-label={t('transactions.allCategories', 'All categories')}
            className="h-7 min-w-0 flex-1 rounded-md border border-input bg-transparent px-2 text-xs outline-none focus-visible:border-ring focus-visible:ring-2 focus-visible:ring-ring/40 disabled:opacity-50"
          >
            <option value="">{t('transactions.allCategories', 'All categories')}</option>
            {categories.map((c) => (
              <option key={c.id} value={c.id}>
                {c.emoji ? `${c.emoji} ` : ''}
                {c.groupName} / {c.name}
              </option>
            ))}
          </select>
          <select
            value={limit}
            onChange={(e) => {
              const next = Number(e.target.value)
              setLimit(next)
              refresh({ limit: next })
            }}
            disabled={pending}
            aria-label={t('dashboard.resultCount', 'How many')}
            className="h-7 rounded-md border border-input bg-transparent px-2 text-xs outline-none focus-visible:border-ring focus-visible:ring-2 focus-visible:ring-ring/40 disabled:opacity-50"
          >
            {COUNT_OPTIONS.map((n) => (
              <option key={n} value={n}>
                {t('dashboard.topN', { n }, `Top ${n}`)}
              </option>
            ))}
          </select>
          <input
            type="number"
            inputMode="decimal"
            step="1"
            min="0"
            value={minDraft}
            onChange={(e) => setMinDraft(e.target.value)}
            onBlur={() => refresh({ minAmount: parseDecimalInput(minDraft, 0) })}
            onKeyDown={(e) => {
              if (e.key === 'Enter') (e.target as HTMLInputElement).blur()
            }}
            disabled={pending}
            placeholder={t('dashboard.minAmountPlaceholder', 'Min €')}
            aria-label={t('dashboard.minAmountLabel', 'Minimum amount')}
            className="h-7 w-[72px] rounded-md border border-input bg-transparent px-2 text-xs outline-none focus-visible:border-ring focus-visible:ring-2 focus-visible:ring-ring/40 disabled:opacity-50"
          />
        </div>
      </CardHeader>
      <CardContent className="min-h-0 flex-1 overflow-auto pb-3">
        {items.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            {pending
              ? t('dashboard.loadingShort', 'Loading…')
              : t('dashboard.emptyWindow', 'Nothing in this window.')}
          </p>
        ) : (
          <ul className={`space-y-2 ${pending ? 'opacity-50' : ''}`}>
            {items.map((it) => (
              <li key={it.id} className="flex items-center justify-between gap-2 text-sm">
                <div className="min-w-0 flex-1">
                  <p className="truncate font-medium">
                    {it.label || t('dashboard.noPayee', '(no payee)')}
                  </p>
                  <p className="truncate text-xs text-muted-foreground">
                    {it.count !== null
                      ? t('dashboard.charges', { n: it.count }, '{n} charges')
                      : `${it.date ? new Date(it.date).toLocaleDateString('fr-FR') : ''} · ${
                          it.categoryName ?? t('dashboard.uncategorizedShort', 'Uncategorized')
                        }`}
                  </p>
                </div>
                <div className="shrink-0 text-right">
                  <span className="tabular-nums text-destructive">−{formatCurrency(it.amount)}</span>
                  <p className="text-[11px] text-muted-foreground tabular-nums">
                    {Math.round(it.pctOfPeriod)}% {t('dashboard.ofSpend', 'of spend')}
                  </p>
                </div>
              </li>
            ))}
          </ul>
        )}
      </CardContent>
    </Card>
  )
}
