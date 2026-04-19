'use client'

import { useTransition } from 'react'
import { type CategoryOption, CategoryPicker } from '../ui/category-picker'
import type { ActionResult } from '../../types/index'

interface TxBulkActionBarProps {
  selectedIds: ReadonlyArray<string>
  categoryOptions: ReadonlyArray<CategoryOption>
  onDone: () => void
  onBulkSoftDeleteTransactions: (
    ids: ReadonlyArray<string>,
  ) => Promise<ActionResult<{ deleted: number }>>
  onBulkUpdateTransactionCategory: (
    ids: ReadonlyArray<string>,
    categoryId: string | null,
  ) => Promise<ActionResult<{ updated: number }>>
}

/**
 * Sticky bar shown above the Transactions list when at least one row is
 * selected. Offers bulk categorize + bulk delete. No approve action since
 * rows on this page are already approved (Review page has its own bar).
 */
export function TxBulkActionBar({
  selectedIds,
  categoryOptions,
  onDone,
  onBulkSoftDeleteTransactions,
  onBulkUpdateTransactionCategory,
}: TxBulkActionBarProps) {
  const [pending, startTransition] = useTransition()
  const count = selectedIds.length

  const onCategorize = (categoryId: string | null) => {
    startTransition(async () => {
      await onBulkUpdateTransactionCategory(selectedIds, categoryId)
      onDone()
    })
  }

  const onDelete = () => {
    const ok = window.confirm(
      `Delete ${count} transaction${count === 1 ? '' : 's'}? This can't be undone from the UI.`,
    )
    if (!ok) return
    startTransition(async () => {
      await onBulkSoftDeleteTransactions(selectedIds)
      onDone()
    })
  }

  return (
    <div className="sticky top-0 z-20 flex flex-wrap items-center justify-between gap-2 border-b border-border bg-background/95 px-3 py-2 text-xs backdrop-blur supports-[backdrop-filter]:bg-background/80">
      <div className="flex items-center gap-2">
        <span className="rounded-full bg-foreground/10 px-2 py-0.5 text-[11px] font-medium text-foreground">
          {count} selected
        </span>
        <button
          type="button"
          onClick={onDone}
          disabled={pending}
          className="text-[11px] text-muted-foreground underline-offset-2 hover:text-foreground hover:underline disabled:opacity-50"
        >
          Clear
        </button>
      </div>
      <div className="flex flex-wrap items-center gap-2">
        <CategoryPicker
          options={categoryOptions}
          onPick={onCategorize}
          disabled={pending}
          showClear
          align="right"
          trigger={
            <span className="inline-flex items-center gap-1 rounded-md border border-border bg-background px-2 py-1 text-[11px] font-medium text-foreground hover:bg-muted">
              Categorize as… <span className="text-muted-foreground/60">▾</span>
            </span>
          }
        />
        <button
          type="button"
          onClick={onDelete}
          disabled={pending}
          className="rounded-md border border-destructive/40 bg-destructive/10 px-2 py-1 text-[11px] font-medium text-destructive hover:bg-destructive/20 disabled:opacity-50"
        >
          Delete
        </button>
      </div>
    </div>
  )
}
