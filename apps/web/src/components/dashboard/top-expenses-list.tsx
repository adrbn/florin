'use client'

import { useState, useTransition } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { formatCurrency } from '@/lib/format/currency'
import { fetchTopExpenses } from '@/server/actions/dashboard'

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

interface TopExpensesListProps {
  initial: ReadonlyArray<SerializedExpense>
  categories: ReadonlyArray<CategoryOption>
  defaultDays: number
}

const DAY_OPTIONS = [7, 30, 60, 90, 180, 365] as const

export function TopExpensesList({ initial, categories, defaultDays }: TopExpensesListProps) {
  const [days, setDays] = useState<number>(defaultDays)
  const [categoryId, setCategoryId] = useState<string>('') // '' = all
  const [items, setItems] = useState<ReadonlyArray<SerializedExpense>>(initial)
  const [pending, startTransition] = useTransition()

  const refresh = (nextDays: number, nextCategoryId: string): void => {
    startTransition(async () => {
      const data = await fetchTopExpenses(nextDays, nextCategoryId === '' ? null : nextCategoryId)
      setItems(data.map((e) => ({ ...e, date: e.date.toISOString() })))
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
          <CardTitle className="text-base">Top 5 expenses</CardTitle>
        </div>
        <div className="flex flex-wrap gap-2">
          <select
            value={days}
            onChange={onDaysChange}
            disabled={pending}
            aria-label="Time window"
            className="h-7 rounded-md border border-input bg-transparent px-2 text-xs outline-none focus-visible:border-ring focus-visible:ring-2 focus-visible:ring-ring/40 disabled:opacity-50"
          >
            {DAY_OPTIONS.map((d) => (
              <option key={d} value={d}>
                Last {d} days
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
            <option value="">All categories</option>
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
            {pending ? 'Loading…' : 'Nothing in this window.'}
          </p>
        ) : (
          <ul className={`space-y-2 ${pending ? 'opacity-50' : ''}`}>
            {items.map((t) => (
              <li key={t.id} className="flex items-center justify-between gap-2 text-sm">
                <div className="min-w-0 flex-1">
                  <p className="truncate font-medium">{t.payee || '(no payee)'}</p>
                  <p className="truncate text-xs text-muted-foreground">
                    {new Date(t.date).toLocaleDateString('fr-FR')} ·{' '}
                    {t.categoryName ?? 'Uncategorized'}
                  </p>
                </div>
                <span className="shrink-0 font-mono text-destructive">
                  −{formatCurrency(t.amount)}
                </span>
              </li>
            ))}
          </ul>
        )}
      </CardContent>
    </Card>
  )
}
