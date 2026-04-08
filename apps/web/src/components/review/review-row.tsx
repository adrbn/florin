'use client'

import { useTransition } from 'react'
import { TransactionCategoryCell } from '@/components/transactions/transaction-category-cell'
import { approveTransaction, softDeleteTransaction } from '@/server/actions/transactions'

interface CategoryOption {
  id: string
  name: string
  emoji: string | null
  groupName: string
}

interface ReviewRowProps {
  transactionId: string
  date: string
  payee: string
  accountName: string
  amount: number
  amountFormatted: string
  currentCategoryId: string | null
  currentCategoryName: string | null
  currentCategoryEmoji: string | null
  categoryOptions: ReadonlyArray<CategoryOption>
  selected: boolean
  onToggleSelect: () => void
}

/**
 * One row in the review queue.
 *
 * Desktop (md+): a 7-column grid (checkbox, date, payee, account, category,
 * amount, actions) whose resizable column widths come from the parent
 * ReviewTable via CSS custom properties. The actions cell holds both the
 * approve (✓) and delete (🗑) buttons.
 *
 * Mobile (<md): a stacked two-row card — checkbox + date + payee + account
 * on line 1, category picker + amount + action cluster on line 2.
 * `md:contents` collapses the per-row wrappers away on desktop so the grid
 * sees a flat list of cells.
 */
export function ReviewRow({
  transactionId,
  date,
  payee,
  accountName,
  amount,
  amountFormatted,
  currentCategoryId,
  currentCategoryName,
  currentCategoryEmoji,
  categoryOptions,
  selected,
  onToggleSelect,
}: ReviewRowProps) {
  const [pending, startTransition] = useTransition()
  const isNegative = amount < 0

  const onApprove = () => {
    startTransition(async () => {
      await approveTransaction(transactionId)
    })
  }

  const onDelete = () => {
    const ok = window.confirm('Delete this transaction?')
    if (!ok) return
    startTransition(async () => {
      await softDeleteTransaction(transactionId)
    })
  }

  return (
    <div
      className={`flex flex-col gap-1.5 px-3 py-2.5 text-xs hover:bg-muted/40 md:grid md:grid-cols-[32px_var(--col-date)_minmax(0,1fr)_var(--col-account)_var(--col-category)_var(--col-amount)_var(--col-actions)] md:items-center md:gap-3 md:py-2 ${
        selected ? 'bg-foreground/[0.03]' : ''
      }`}
    >
      {/* Line 1 — metadata. md:contents promotes the children straight into
          the grid so they line up with the header. */}
      <div className="flex min-w-0 items-center gap-2 md:contents">
        <input
          type="checkbox"
          aria-label="Select row"
          checked={selected}
          onChange={onToggleSelect}
          className="h-3.5 w-3.5 shrink-0 cursor-pointer rounded border-border accent-foreground md:justify-self-center"
        />
        <span className="shrink-0 font-mono text-[11px] text-muted-foreground md:text-xs">
          {date}
        </span>
        <span
          className="min-w-0 flex-1 truncate font-medium text-foreground md:flex-initial"
          title={payee}
        >
          {payee}
        </span>
        <span
          className="shrink-0 truncate text-[11px] text-muted-foreground md:text-xs"
          title={accountName}
        >
          {accountName}
        </span>
      </div>
      {/* Line 2 — category picker + amount + action cluster. */}
      <div className="flex min-w-0 items-center justify-between gap-2 md:contents">
        <div className="min-w-0">
          <TransactionCategoryCell
            transactionId={transactionId}
            currentCategoryId={currentCategoryId}
            currentCategoryName={currentCategoryName}
            currentCategoryEmoji={currentCategoryEmoji}
            options={categoryOptions}
          />
        </div>
        <span
          className={`shrink-0 font-mono tabular-nums md:text-right ${
            isNegative ? 'text-destructive' : 'text-emerald-600'
          }`}
        >
          {amountFormatted}
        </span>
        <div className="flex shrink-0 items-center gap-1 md:justify-self-center">
          <button
            type="button"
            onClick={onApprove}
            disabled={pending}
            className="rounded-md border border-emerald-500/40 bg-emerald-500/10 px-2 py-1 text-[11px] font-medium text-emerald-700 hover:bg-emerald-500/20 disabled:opacity-50 dark:text-emerald-300"
            title="Mark as reviewed"
          >
            {pending ? '…' : '✓'}
          </button>
          <button
            type="button"
            onClick={onDelete}
            disabled={pending}
            className="rounded-md border border-destructive/40 bg-destructive/10 px-1.5 py-1 text-[11px] font-medium text-destructive hover:bg-destructive/20 disabled:opacity-50"
            title="Delete transaction"
            aria-label="Delete transaction"
          >
            🗑
          </button>
        </div>
      </div>
    </div>
  )
}
