'use client'

import { useEffect, useState } from 'react'
import type { ListPlanCategoryTransactions, PlanCategoryTransaction } from '@florin/core/types'
import { formatCurrency } from '@florin/core/lib/format'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '../ui/dialog'
import { useT } from '../../i18n/context'

interface PlanCategoryTransactionsModalProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  category: { id: string; name: string; emoji: string | null } | null
  year: number
  month: number
  onListTransactions: ListPlanCategoryTransactions
}

const MONTH_KEYS = [
  'plan.monthJan', 'plan.monthFeb', 'plan.monthMar', 'plan.monthApr', 'plan.monthMay', 'plan.monthJun',
  'plan.monthJul', 'plan.monthAug', 'plan.monthSep', 'plan.monthOct', 'plan.monthNov', 'plan.monthDec',
] as const
const MONTH_FALLBACKS = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
] as const

export function PlanCategoryTransactionsModal({
  open,
  onOpenChange,
  category,
  year,
  month,
  onListTransactions,
}: PlanCategoryTransactionsModalProps) {
  const t = useT()
  const [rows, setRows] = useState<PlanCategoryTransaction[] | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!open || !category) return
    let cancelled = false
    setRows(null)
    setError(null)
    onListTransactions(category.id, year, month)
      .then((data) => {
        if (!cancelled) setRows(data)
      })
      .catch((e: unknown) => {
        if (!cancelled) setError(e instanceof Error ? e.message : t('plan.modalFailedToLoad', 'Failed to load transactions'))
      })
    return () => {
      cancelled = true
    }
  }, [open, category, year, month, onListTransactions, t])

  function formatDay(iso: string): string {
    const d = new Date(iso)
    const day = d.getUTCDate().toString().padStart(2, '0')
    const mon = t(MONTH_KEYS[d.getUTCMonth()]!, MONTH_FALLBACKS[d.getUTCMonth()]!)
    return `${day} ${mon}`
  }

  const total = rows?.reduce((s, r) => s + r.amount, 0) ?? 0
  const monthLabel = `${t(MONTH_KEYS[month - 1]!, MONTH_FALLBACKS[month - 1]!)} ${year}`

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-lg max-h-[80vh] flex flex-col overflow-hidden">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2 pr-8">
            {category?.emoji ? <span>{category.emoji}</span> : null}
            <span>{category?.name ?? t('plan.category', 'Category')}</span>
            <span className="ml-auto text-xs font-normal text-muted-foreground">{monthLabel}</span>
          </DialogTitle>
        </DialogHeader>

        <div className="flex-1 min-h-0 overflow-y-auto -mx-4 px-4">
          {rows === null && !error ? (
            <div className="py-8 text-center text-sm text-muted-foreground">{t('plan.loading', 'Loading…')}</div>
          ) : error ? (
            <div className="py-8 text-center text-sm text-red-500">{error}</div>
          ) : rows && rows.length === 0 ? (
            <div className="py-8 text-center text-sm text-muted-foreground">
              {t('plan.noTransactionsThisMonth', 'No transactions this month.')}
            </div>
          ) : rows ? (
            <ul className="divide-y divide-border text-sm">
              {rows.map((tx) => (
                <li key={tx.id} className="flex items-start gap-3 py-2">
                  <div className="w-14 shrink-0 text-xs text-muted-foreground pt-0.5">
                    {formatDay(tx.occurredAt)}
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="truncate">{tx.payee || '—'}</div>
                    {tx.memo ? (
                      <div className="truncate text-xs text-muted-foreground">{tx.memo}</div>
                    ) : null}
                  </div>
                  <div
                    className={`shrink-0 tabular-nums font-medium ${
                      tx.amount < 0 ? 'text-foreground' : 'text-emerald-500'
                    }`}
                  >
                    {formatCurrency(tx.amount)}
                  </div>
                </li>
              ))}
            </ul>
          ) : null}
        </div>

        {rows && rows.length > 0 ? (
          <div className="border-t border-border pt-2 flex items-center justify-between text-sm">
            <span className="text-muted-foreground">
              {rows.length} {rows.length > 1 ? t('plan.transactions', 'transactions') : t('plan.transaction', 'transaction')}
            </span>
            <span className="font-semibold tabular-nums">{formatCurrency(total)}</span>
          </div>
        ) : null}
      </DialogContent>
    </Dialog>
  )
}
