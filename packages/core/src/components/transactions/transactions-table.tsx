'use client'

import { type CSSProperties, useCallback, useEffect, useState } from 'react'
import { DeleteTransactionButton } from '../transactions/delete-transaction-button'
import { TransactionCategoryCell } from '../transactions/transaction-category-cell'
import type { ActionResult } from '../../types/index'
import type { CategoryOption } from '../ui/category-picker'
import { formatCurrencySigned } from '../../lib/format/currency'

export interface TransactionRowData {
  id: string
  date: string
  payee: string
  accountName: string
  amount: number
  currentCategoryId: string | null
  currentCategoryName: string | null
  currentCategoryEmoji: string | null
}

export interface TransactionsTableActions {
  onUpdateTransactionCategory: (transactionId: string, categoryId: string | null) => Promise<ActionResult>
  onSoftDeleteTransaction: (id: string) => Promise<ActionResult>
}

interface TransactionsTableProps {
  rows: ReadonlyArray<TransactionRowData>
  categoryOptions: ReadonlyArray<CategoryOption>
  emptyMessage: string
  actions: TransactionsTableActions
}

type ColKey = 'date' | 'account' | 'category' | 'amount' | 'actions'

const DEFAULT_WIDTHS: Record<ColKey, number> = {
  date: 80,
  account: 130,
  category: 170,
  amount: 110,
  actions: 48,
}
const MIN_WIDTH = 48
const MAX_WIDTH = 400
const STORAGE_KEY = 'florin.transactions.columnWidths.v1'

/**
 * Transactions table. Mirrors ReviewTable's resizable grid so the two pages
 * share the same look and feel:
 *   - desktop: CSS grid with custom property column widths, header shows
 *     draggable resize handles, no horizontal overflow
 *   - mobile: stacked two-row card layout so nothing clips
 * Unlike Review, there's no checkbox column (the page is read-only aside from
 * category edits + delete), so the grid template is one track shorter.
 */
export function TransactionsTable({ rows, categoryOptions, emptyMessage, actions }: TransactionsTableProps) {
  const [widths, setWidths] = useState<Record<ColKey, number>>(DEFAULT_WIDTHS)

  useEffect(() => {
    try {
      const raw = localStorage.getItem(STORAGE_KEY)
      if (!raw) return
      const parsed = JSON.parse(raw) as unknown
      if (parsed && typeof parsed === 'object') {
        const next: Record<ColKey, number> = { ...DEFAULT_WIDTHS }
        for (const key of Object.keys(DEFAULT_WIDTHS) as ColKey[]) {
          const value = (parsed as Record<string, unknown>)[key]
          if (typeof value === 'number' && Number.isFinite(value)) {
            next[key] = Math.min(MAX_WIDTH, Math.max(MIN_WIDTH, value))
          }
        }
        setWidths(next)
      }
    } catch {
      // localStorage can throw in private mode — defaults are fine.
    }
  }, [])

  useEffect(() => {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(widths))
    } catch {
      // Same — non-fatal.
    }
  }, [widths])

  const startResize = useCallback(
    (col: ColKey, event: React.MouseEvent) => {
      event.preventDefault()
      event.stopPropagation()
      const startX = event.clientX
      const startWidth = widths[col]
      const onMove = (e: MouseEvent) => {
        const dx = e.clientX - startX
        const next = Math.min(MAX_WIDTH, Math.max(MIN_WIDTH, startWidth + dx))
        setWidths((prev) => (prev[col] === next ? prev : { ...prev, [col]: next }))
      }
      const onUp = () => {
        document.removeEventListener('mousemove', onMove)
        document.removeEventListener('mouseup', onUp)
        document.body.style.cursor = ''
        document.body.style.userSelect = ''
      }
      document.addEventListener('mousemove', onMove)
      document.addEventListener('mouseup', onUp)
      document.body.style.cursor = 'col-resize'
      document.body.style.userSelect = 'none'
    },
    [widths],
  )

  const style = {
    '--col-date': `${widths.date}px`,
    '--col-account': `${widths.account}px`,
    '--col-category': `${widths.category}px`,
    '--col-amount': `${widths.amount}px`,
    '--col-actions': `${widths.actions}px`,
  } as CSSProperties

  if (rows.length === 0) {
    return <div className="py-12 text-center text-sm text-muted-foreground">{emptyMessage}</div>
  }

  return (
    <div style={style}>
      <div className="divide-y divide-border/60">
        {/* Header row — desktop only. */}
        <div className="hidden border-b border-border bg-muted/40 px-3 py-2 text-[10px] font-medium uppercase tracking-wide text-muted-foreground md:grid md:grid-cols-[var(--col-date)_minmax(0,1fr)_var(--col-account)_var(--col-category)_var(--col-amount)_var(--col-actions)] md:items-center md:gap-3">
          <ResizableHeader label="Date" onStart={(e) => startResize('date', e)} />
          <span className="truncate">Payee</span>
          <ResizableHeader label="Account" onStart={(e) => startResize('account', e)} />
          <ResizableHeader label="Category" onStart={(e) => startResize('category', e)} />
          <ResizableHeader label="Amount" align="right" onStart={(e) => startResize('amount', e)} />
          <span className="text-center" aria-label="Actions" />
        </div>
        {rows.map((row) => (
          <TransactionRow key={row.id} row={row} categoryOptions={categoryOptions} actions={actions} />
        ))}
      </div>
    </div>
  )
}

interface TransactionRowProps {
  row: TransactionRowData
  categoryOptions: ReadonlyArray<CategoryOption>
  actions: TransactionsTableActions
}

function TransactionRow({ row, categoryOptions, actions }: TransactionRowProps) {
  const isNegative = row.amount < 0
  return (
    <div className="flex flex-col gap-1.5 px-3 py-2.5 text-xs hover:bg-muted/40 md:grid md:grid-cols-[var(--col-date)_minmax(0,1fr)_var(--col-account)_var(--col-category)_var(--col-amount)_var(--col-actions)] md:items-center md:gap-3 md:py-2">
      {/* Line 1 (mobile) / flattened onto the grid (desktop) */}
      <div className="flex min-w-0 items-center gap-2 md:contents">
        <span className="shrink-0 font-mono text-[11px] text-muted-foreground md:text-xs">
          {row.date}
        </span>
        <span
          className="min-w-0 flex-1 truncate font-medium text-foreground md:flex-initial"
          title={row.payee}
        >
          {row.payee}
        </span>
        <span
          className="shrink-0 truncate text-[11px] text-muted-foreground md:text-xs"
          title={row.accountName}
        >
          {row.accountName}
        </span>
      </div>
      {/* Line 2 (mobile) / continuation of the grid (desktop) */}
      <div className="flex min-w-0 items-center justify-between gap-2 md:contents">
        <div className="min-w-0">
          <TransactionCategoryCell
            transactionId={row.id}
            currentCategoryId={row.currentCategoryId}
            currentCategoryName={row.currentCategoryName}
            currentCategoryEmoji={row.currentCategoryEmoji}
            options={categoryOptions}
            onUpdateTransactionCategory={actions.onUpdateTransactionCategory}
          />
        </div>
        <span
          className={`shrink-0 font-mono tabular-nums md:text-right ${
            isNegative ? 'text-destructive' : 'text-emerald-600'
          }`}
        >
          {formatCurrencySigned(row.amount)}
        </span>
        <div className="flex shrink-0 items-center md:justify-self-center">
          <DeleteTransactionButton
            transactionId={row.id}
            payee={row.payee}
            onSoftDeleteTransaction={actions.onSoftDeleteTransaction}
          />
        </div>
      </div>
    </div>
  )
}

interface ResizableHeaderProps {
  label: string
  align?: 'left' | 'right' | 'center'
  onStart: (event: React.MouseEvent) => void
}

/**
 * Column header label with a draggable hit area pinned to its right edge.
 * Copied from ReviewTable so the two tables feel identical under the hand.
 */
function ResizableHeader({ label, align = 'left', onStart }: ResizableHeaderProps) {
  const alignClass = align === 'right' ? 'text-right' : align === 'center' ? 'text-center' : ''
  return (
    <div className="relative min-w-0">
      <span className={`block truncate ${alignClass}`}>{label}</span>
      <button
        type="button"
        aria-label={`Resize ${label} column`}
        onMouseDown={onStart}
        className="group absolute -right-1.5 top-0 z-10 flex h-full w-3 cursor-col-resize items-center justify-center focus:outline-none"
      >
        <span className="h-4 w-px bg-border transition-colors group-hover:bg-foreground/60 group-active:bg-foreground" />
      </button>
    </div>
  )
}
