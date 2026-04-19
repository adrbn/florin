'use client'

import { useState, useTransition } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '../ui/card'
import { useT } from '../../i18n/context'
import { formatCurrency } from '../../lib/format/currency'

interface SerializedExpense {
  id: string
  payee: string
  date: string
  amount: number
  categoryName: string | null
}

interface CategoryOption {
  id: string
  name: string
  emoji: string | null
  groupName: string
}

export interface TopExpensesListProps {
  initial: ReadonlyArray<SerializedExpense>
  categories: ReadonlyArray<CategoryOption>
  defaultDays: number
  onFetchTopExpenses: (days: number, categoryId: string | null) => Promise<ReadonlyArray<SerializedExpense>>
}

const DAY_OPTIONS = [7, 30, 60, 90, 180, 365] as const

export function TopExpensesList({ initial, categories, defaultDays, onFetchTopExpenses }: TopExpensesListProps) {
  const t = useT()
  const [days, setDays] = useState<number>(defaultDays)
  const [categoryId, setCategoryId] = useState<string>('') // '' = all
  const [items, setItems] = useState<ReadonlyArray<SerializedExpense>>(initial)
  const [pending, startTransition] = useTransition()

  const refresh = (nextDays: number, nextCategoryId: string): void => {
    startTransition(async () => {
      const data = await onFetchTopExpenses(nextDays, nextCategoryId === '' ? null : nextCategoryId)
      setItems(data)
    })
  }

  const onDaysChange = (e: React.ChangeEvent<HTMLSelectElement>): void => {
    const next = Number(e.target.value)
    setDays(next)
    refresh(next, categoryId)
  }

  const onCategoryChange = (e: React.ChangeEvent<HTMLSelectElement>): void => {
    const next = e.target.value
    setCategoryId(next)
    refresh(days, next)
  }

  return (
    <Card className="flex h-full flex-col">
      <CardHeader className="space-y-2 pb-2">
        <div className="flex items-center justify-between gap-2">
          <CardTitle className="text-base">{t('dashboard.top5Expenses', 'Top 5 expenses')}</CardTitle>
        </div>
        <div className="flex flex-wrap gap-2">
          <select
            value={days}
            onChange={onDaysChange}
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
            onChange={onCategoryChange}
            disabled={pending}
            aria-label="Category filter"
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
        </div>
      </CardHeader>
      <CardContent className="min-h-0 flex-1 overflow-auto pb-3">
        {items.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            {pending ? t('dashboard.loadingShort', 'Loading…') : t('dashboard.emptyWindow', 'Nothing in this window.')}
          </p>
        ) : (
          <ul className={`space-y-2 ${pending ? 'opacity-50' : ''}`}>
            {items.map((tx) => (
              <li key={tx.id} className="flex items-center justify-between gap-2 text-sm">
                <div className="min-w-0 flex-1">
                  <p className="truncate font-medium">{tx.payee || t('dashboard.noPayee', '(no payee)')}</p>
                  <p className="truncate text-xs text-muted-foreground">
                    {new Date(tx.date).toLocaleDateString('fr-FR')} ·{' '}
                    {tx.categoryName ?? t('dashboard.uncategorizedShort', 'Uncategorized')}
                  </p>
                </div>
                <span className="shrink-0 tabular-nums text-destructive">
                  −{formatCurrency(tx.amount)}
                </span>
              </li>
            ))}
          </ul>
        )}
      </CardContent>
    </Card>
  )
}
