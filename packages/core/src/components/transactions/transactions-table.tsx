'use client'

import { type CSSProperties, useCallback, useEffect, useMemo, useState } from 'react'
import { DeleteTransactionButton } from '../transactions/delete-transaction-button'
import { TransactionCategoryCell } from '../transactions/transaction-category-cell'
import { TxBulkActionBar } from './tx-bulk-action-bar'
import type { ActionResult } from '../../types/index'
import type { CategoryOption } from '../ui/category-picker'
import { formatCurrencySigned } from '../../lib/format/currency'
import { useT } from '../../i18n/context'

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
  onUpdateTransactionCategory: (
    transactionId: string,
    categoryId: string | null,
  ) => Promise<ActionResult>
  onSoftDeleteTransaction: (id: string) => Promise<ActionResult>
  onBulkUpdateTransactionCategory?: (
    ids: ReadonlyArray<string>,
    categoryId: string | null,
  ) => Promise<ActionResult<{ updated: number }>>
  onBulkSoftDeleteTransactions?: (
    ids: ReadonlyArray<string>,
  ) => Promise<ActionResult<{ deleted: number }>>
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
 * Transactions table. Mirrors ReviewTable's resizable grid + checkbox
 * selection so the two pages share the same look and feel. When bulk
 * actions are wired (both onBulk* props provided), the checkbox column
 * activates and a sticky TxBulkActionBar appears whenever a row is picked.
 */
export function TransactionsTable({
  rows,
  categoryOptions,
  emptyMessage,
  actions,
}: TransactionsTableProps) {
  const t = useT()
  const [widths, setWidths] = useState<Record<ColKey, number>>(DEFAULT_WIDTHS)
  const [selected, setSelected] = useState<ReadonlySet<string>>(() => new Set())
  const selectable = Boolean(
    actions.onBulkUpdateTransactionCategory && actions.onBulkSoftDeleteTransactions,
  )

  useEffect(() => {
    if (!selectable) return
    setSelected((prev) => {
      const alive = new Set(rows.map((r) => r.id))
      let changed = false
      const next = new Set<string>()
      for (const id of prev) {
        if (alive.has(id)) next.add(id)
        else changed = true
      }
      return changed ? next : prev
    })
  }, [rows, selectable])

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
        // Flip dx so dragging LEFT narrows the column on the right of the handle
        // (which is what users instinctively expect when the handle sits between
        // two columns and they pull it toward the one they want to shrink).
        const next = Math.min(MAX_WIDTH, Math.max(MIN_WIDTH, startWidth - dx))
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

  const toggleOne = useCallback((id: string) => {
    setSelected((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }, [])

  const toggleAll = useCallback(() => {
    setSelected((prev) => {
      if (prev.size === rows.length) return new Set()
      return new Set(rows.map((r) => r.id))
    })
  }, [rows])

  const clearSelection = useCallback(() => {
    setSelected(new Set())
  }, [])

  const selectedIds = useMemo(() => Array.from(selected), [selected])
  const allChecked = rows.length > 0 && selected.size === rows.length
  const someChecked = selected.size > 0 && selected.size < rows.length

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

  const gridCols = selectable
    ? 'md:grid-cols-[32px_var(--col-date)_minmax(0,1fr)_var(--col-account)_var(--col-category)_var(--col-amount)_var(--col-actions)]'
    : 'md:grid-cols-[var(--col-date)_minmax(0,1fr)_var(--col-account)_var(--col-category)_var(--col-amount)_var(--col-actions)]'

  return (
    <div style={style}>
      {selectable && selected.size > 0 && (
        <TxBulkActionBar
          selectedIds={selectedIds}
          categoryOptions={categoryOptions}
          onDone={clearSelection}
          onBulkSoftDeleteTransactions={actions.onBulkSoftDeleteTransactions!}
          onBulkUpdateTransactionCategory={actions.onBulkUpdateTransactionCategory!}
        />
      )}
      <div className="divide-y divide-border/60">
        <div
          className={`hidden border-b border-border bg-muted/40 px-3 py-2 text-[10px] font-medium uppercase tracking-wide text-muted-foreground md:grid md:items-center md:gap-3 ${gridCols}`}
        >
          {selectable && (
            <span className="flex items-center justify-center">
              <HeaderCheckbox
                checked={allChecked}
                indeterminate={someChecked}
                onToggle={toggleAll}
                disabled={rows.length === 0}
              />
            </span>
          )}
          <ResizableHeader label={t('review.colDate', 'Date')} onStart={(e) => startResize('date', e)} />
          <span className="truncate">{t('transactions.payee', 'Payee')}</span>
          <ResizableHeader label={t('transactions.account', 'Account')} onStart={(e) => startResize('account', e)} />
          <ResizableHeader label={t('transactions.category', 'Category')} onStart={(e) => startResize('category', e)} />
          <ResizableHeader
            label={t('review.colAmount', 'Amount')}
            align="right"
            onStart={(e) => startResize('amount', e)}
          />
          <span className="text-center" aria-label={t('transactions.actions', 'Actions')} />
        </div>
        {rows.map((row) => (
          <TransactionRow
            key={row.id}
            row={row}
            categoryOptions={categoryOptions}
            actions={actions}
            selectable={selectable}
            selected={selected.has(row.id)}
            onToggleSelect={() => toggleOne(row.id)}
            gridCols={gridCols}
          />
        ))}
      </div>
    </div>
  )
}

interface TransactionRowProps {
  row: TransactionRowData
  categoryOptions: ReadonlyArray<CategoryOption>
  actions: TransactionsTableActions
  selectable: boolean
  selected: boolean
  onToggleSelect: () => void
  gridCols: string
}

function TransactionRow({
  row,
  categoryOptions,
  actions,
  selectable,
  selected,
  onToggleSelect,
  gridCols,
}: TransactionRowProps) {
  const isNegative = row.amount < 0
  return (
    <div
      className={`flex flex-col gap-1.5 px-3 py-2.5 text-xs hover:bg-muted/40 md:grid md:items-center md:gap-3 md:py-2 ${gridCols} ${
        selected ? 'bg-muted/30' : ''
      }`}
    >
      {selectable && (
        <span className="hidden md:flex md:items-center md:justify-center">
          <input
            type="checkbox"
            aria-label={`Select ${row.payee}`}
            checked={selected}
            onChange={onToggleSelect}
            className="h-3.5 w-3.5 cursor-pointer rounded border-border accent-foreground"
          />
        </span>
      )}
      <div className="flex min-w-0 items-center gap-2 md:contents">
        {selectable && (
          <input
            type="checkbox"
            aria-label={`Select ${row.payee}`}
            checked={selected}
            onChange={onToggleSelect}
            className="h-3.5 w-3.5 shrink-0 cursor-pointer rounded border-border accent-foreground md:hidden"
          />
        )}
        <span className="shrink-0 tabular-nums text-[11px] text-muted-foreground md:text-xs">
          {row.date}
        </span>
        <span
          className="min-w-0 flex-1 truncate font-medium text-foreground md:flex-initial"
          title={row.payee}
          data-amount="manual"
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
          className={`shrink-0 tabular-nums md:text-right ${
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

interface HeaderCheckboxProps {
  checked: boolean
  indeterminate: boolean
  onToggle: () => void
  disabled?: boolean
}

function HeaderCheckbox({ checked, indeterminate, onToggle, disabled }: HeaderCheckboxProps) {
  return (
    <input
      type="checkbox"
      aria-label="Select all rows"
      checked={checked}
      disabled={disabled}
      ref={(el) => {
        if (el) el.indeterminate = indeterminate
      }}
      onChange={onToggle}
      className="h-3.5 w-3.5 cursor-pointer rounded border-border accent-foreground disabled:cursor-not-allowed disabled:opacity-50"
    />
  )
}

interface ResizableHeaderProps {
  label: string
  align?: 'left' | 'right' | 'center'
  onStart: (event: React.MouseEvent) => void
}

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
