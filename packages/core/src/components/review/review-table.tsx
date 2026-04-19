'use client'

import { type CSSProperties, useCallback, useEffect, useMemo, useState } from 'react'
import { useT } from '../../i18n/context'
import type { ActionResult } from '../../types/index'
import type { CategoryOption } from '../ui/category-picker'
import { BulkActionBar } from './bulk-action-bar'
import { ReviewRow } from './review-row'

export interface ReviewRowData {
  transactionId: string
  date: string
  payee: string
  accountName: string
  amount: number
  amountFormatted: string
  currentCategoryId: string | null
  currentCategoryName: string | null
  currentCategoryEmoji: string | null
}

export interface ReviewTableActions {
  onApproveTransaction: (id: string) => Promise<ActionResult>
  onSoftDeleteTransaction: (id: string) => Promise<ActionResult>
  onUpdateTransactionCategory: (transactionId: string, categoryId: string | null) => Promise<ActionResult>
  onBulkApproveTransactions: (ids: ReadonlyArray<string>) => Promise<ActionResult<{ approved: number }>>
  onBulkSoftDeleteTransactions: (ids: ReadonlyArray<string>) => Promise<ActionResult<{ deleted: number }>>
  onBulkUpdateTransactionCategory: (ids: ReadonlyArray<string>, categoryId: string | null) => Promise<ActionResult<{ updated: number }>>
}

interface ReviewTableProps {
  rows: ReadonlyArray<ReviewRowData>
  categoryOptions: ReadonlyArray<CategoryOption>
  actions: ReviewTableActions
}

type ColKey = 'date' | 'account' | 'category' | 'amount' | 'actions'

const DEFAULT_WIDTHS: Record<ColKey, number> = {
  date: 80,
  account: 130,
  category: 170,
  amount: 110,
  actions: 96,
}
const MIN_WIDTH = 48
const MAX_WIDTH = 400
const STORAGE_KEY = 'florin.review.columnWidths.v2'

/**
 * Client wrapper around the review list. Owns:
 *   - column-width state (persisted to localStorage) so header drags
 *     propagate to every row via CSS custom properties
 *   - selection state so the user can multi-select rows and batch-categorize,
 *     batch-approve, or batch-delete via the sticky BulkActionBar
 *
 * Mobile (<md) renders rows as stacked two-row cards and hides both the
 * header and the checkbox column — the queue there is consumed one row at
 * a time, not in bulk.
 */
export function ReviewTable({ rows, categoryOptions, actions }: ReviewTableProps) {
  const t = useT()
  const [widths, setWidths] = useState<Record<ColKey, number>>(DEFAULT_WIDTHS)
  const [selected, setSelected] = useState<ReadonlySet<string>>(() => new Set())

  // Drop any stale ids the server no longer returns (e.g. after an approve
  // revalidation) so the bulk bar count doesn't lie.
  useEffect(() => {
    setSelected((prev) => {
      const alive = new Set(rows.map((r) => r.transactionId))
      let changed = false
      const next = new Set<string>()
      for (const id of prev) {
        if (alive.has(id)) {
          next.add(id)
        } else {
          changed = true
        }
      }
      return changed ? next : prev
    })
  }, [rows])

  // Rehydrate persisted widths after mount (keeps SSR deterministic).
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

  const toggleOne = useCallback((id: string) => {
    setSelected((prev) => {
      const next = new Set(prev)
      if (next.has(id)) {
        next.delete(id)
      } else {
        next.add(id)
      }
      return next
    })
  }, [])

  const toggleAll = useCallback(() => {
    setSelected((prev) => {
      if (prev.size === rows.length) return new Set()
      return new Set(rows.map((r) => r.transactionId))
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

  return (
    <div style={style}>
      {selected.size > 0 && (
        <BulkActionBar
          selectedIds={selectedIds}
          categoryOptions={categoryOptions}
          onDone={clearSelection}
          onBulkApproveTransactions={actions.onBulkApproveTransactions}
          onBulkSoftDeleteTransactions={actions.onBulkSoftDeleteTransactions}
          onBulkUpdateTransactionCategory={actions.onBulkUpdateTransactionCategory}
        />
      )}
      <div className="divide-y divide-border/60">
        {/* Header row — desktop only. Mobile hides it and rows become stacked cards. */}
        <div className="hidden border-b border-border bg-muted/40 px-3 py-2 text-[10px] font-medium uppercase tracking-wide text-muted-foreground md:grid md:grid-cols-[32px_var(--col-date)_minmax(0,1fr)_var(--col-account)_var(--col-category)_var(--col-amount)_var(--col-actions)] md:items-center md:gap-3">
          <span className="flex items-center justify-center">
            <HeaderCheckbox
              checked={allChecked}
              indeterminate={someChecked}
              onToggle={toggleAll}
              disabled={rows.length === 0}
              ariaLabel={t('review.selectAllRows', 'Select all rows')}
            />
          </span>
          <ResizableHeader
            label={t('review.colDate', 'Date')}
            onStart={(e) => startResize('date', e)}
            resizeAriaLabel={t('review.resizeColumn', { label: t('review.colDate', 'Date') }, `Resize Date column`)}
          />
          <span className="truncate">{t('review.colPayee', 'Payee')}</span>
          <ResizableHeader
            label={t('review.colAccount', 'Account')}
            onStart={(e) => startResize('account', e)}
            resizeAriaLabel={t('review.resizeColumn', { label: t('review.colAccount', 'Account') }, `Resize Account column`)}
          />
          <ResizableHeader
            label={t('review.colCategory', 'Category')}
            onStart={(e) => startResize('category', e)}
            resizeAriaLabel={t('review.resizeColumn', { label: t('review.colCategory', 'Category') }, `Resize Category column`)}
          />
          <ResizableHeader
            label={t('review.colAmount', 'Amount')}
            align="right"
            onStart={(e) => startResize('amount', e)}
            resizeAriaLabel={t('review.resizeColumn', { label: t('review.colAmount', 'Amount') }, `Resize Amount column`)}
          />
          <ResizableHeader
            label={t('review.colActions', 'Actions')}
            align="center"
            onStart={(e) => startResize('actions', e)}
            resizeAriaLabel={t('review.resizeColumn', { label: t('review.colActions', 'Actions') }, `Resize Actions column`)}
          />
        </div>
        {rows.map((row) => (
          <ReviewRow
            key={row.transactionId}
            {...row}
            categoryOptions={categoryOptions}
            selected={selected.has(row.transactionId)}
            onToggleSelect={() => toggleOne(row.transactionId)}
            onApproveTransaction={actions.onApproveTransaction}
            onSoftDeleteTransaction={actions.onSoftDeleteTransaction}
            onUpdateTransactionCategory={actions.onUpdateTransactionCategory}
          />
        ))}
      </div>
    </div>
  )
}

interface HeaderCheckboxProps {
  checked: boolean
  indeterminate: boolean
  onToggle: () => void
  disabled?: boolean
  ariaLabel: string
}

function HeaderCheckbox({ checked, indeterminate, onToggle, disabled, ariaLabel }: HeaderCheckboxProps) {
  // A raw <input type="checkbox"> handles the indeterminate state via a ref;
  // we keep it tiny here instead of pulling in a whole radix primitive.
  return (
    <input
      type="checkbox"
      aria-label={ariaLabel}
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
  resizeAriaLabel?: string
}

/**
 * A column header label with a draggable hit area pinned to its right edge.
 * The visual resizer is a hair-thin bar that brightens on hover so it stays
 * out of the way until the user reaches for it.
 */
function ResizableHeader({ label, align = 'left', onStart, resizeAriaLabel }: ResizableHeaderProps) {
  const alignClass = align === 'right' ? 'text-right' : align === 'center' ? 'text-center' : ''
  return (
    <div className="relative min-w-0">
      <span className={`block truncate ${alignClass}`}>{label}</span>
      <button
        type="button"
        aria-label={resizeAriaLabel ?? `Resize ${label} column`}
        onMouseDown={onStart}
        className="group absolute -right-1.5 top-0 z-10 flex h-full w-3 cursor-col-resize items-center justify-center focus:outline-none"
      >
        <span className="h-4 w-px bg-border transition-colors group-hover:bg-foreground/60 group-active:bg-foreground" />
      </button>
    </div>
  )
}
