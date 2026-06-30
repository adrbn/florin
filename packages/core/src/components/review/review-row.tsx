'use client'

import { useTransition } from 'react'
import { TransactionCategoryCell } from '../transactions/transaction-category-cell'
import { useT } from '../../i18n/context'
import type { ActionResult } from '../../types/index'
import { MarkAsTransferButton, type AccountOption } from './mark-as-transfer-button'

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
  accountId: string | null
  accountName: string
  amount: number
  amountFormatted: string
  currentCategoryId: string | null
  currentCategoryName: string | null
  currentCategoryEmoji: string | null
  mergeSuggestion?: { candidateTxId: string }
  categoryOptions: ReadonlyArray<CategoryOption>
  accountOptions: ReadonlyArray<AccountOption>
  selected: boolean
  onToggleSelect: () => void
  onApproveTransaction: (id: string) => Promise<ActionResult>
  onSoftDeleteTransaction: (id: string) => Promise<ActionResult>
  onUpdateTransactionCategory: (transactionId: string, categoryId: string | null) => Promise<ActionResult>
  onLinkAsInternalTransfer?: (
    transactionId: string,
    counterpartAccountId: string,
  ) => Promise<ActionResult<{ transferPairId: string; mode: 'paired' | 'created' }>>
  onMergeBankTransaction?: (bankTxId: string, candidateTxId: string) => Promise<ActionResult>
  onDismissMergeSuggestion?: (bankTxId: string) => Promise<ActionResult>
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
  accountId,
  accountName,
  amount,
  amountFormatted,
  currentCategoryId,
  currentCategoryName,
  currentCategoryEmoji,
  mergeSuggestion,
  categoryOptions,
  accountOptions,
  selected,
  onToggleSelect,
  onApproveTransaction,
  onSoftDeleteTransaction,
  onUpdateTransactionCategory,
  onLinkAsInternalTransfer,
  onMergeBankTransaction,
  onDismissMergeSuggestion,
}: ReviewRowProps) {
  const t = useT()
  const [pending, startTransition] = useTransition()
  const isNegative = amount < 0
  const showMergeBanner = Boolean(
    mergeSuggestion && onMergeBankTransaction && onDismissMergeSuggestion,
  )

  const onApprove = () => {
    startTransition(async () => {
      await onApproveTransaction(transactionId)
    })
  }

  const onDelete = () => {
    const ok = window.confirm(t('review.deleteConfirmOne', 'Delete this transaction?'))
    if (!ok) return
    startTransition(async () => {
      await onSoftDeleteTransaction(transactionId)
    })
  }

  const onMerge = () => {
    if (!mergeSuggestion || !onMergeBankTransaction) return
    startTransition(async () => {
      await onMergeBankTransaction(transactionId, mergeSuggestion.candidateTxId)
    })
  }

  const onKeepBoth = () => {
    if (!onDismissMergeSuggestion) return
    startTransition(async () => {
      await onDismissMergeSuggestion(transactionId)
    })
  }

  return (
    <div className={showMergeBanner ? 'border-l-2 border-blue-500/60' : ''}>
      {showMergeBanner && (
        <div className="flex flex-col gap-2 bg-blue-500/[0.06] px-3 py-2 text-xs sm:flex-row sm:items-center sm:justify-between">
          <div className="min-w-0">
            <p className="font-medium text-blue-700 dark:text-blue-300">
              {t('review.mergeSuggestionTitle', 'Doublon possible')}
            </p>
            <p className="text-muted-foreground">
              {t(
                'review.mergeSuggestionBody',
                { amount: amountFormatted, date, payee },
                'This {amount} on {date} matches your planned “{payee}”.',
              )}
            </p>
          </div>
          <div className="flex w-full shrink-0 flex-col gap-1.5 sm:w-auto sm:flex-row sm:items-center">
            <button
              type="button"
              onClick={onMerge}
              disabled={pending}
              className="w-full rounded-md border border-blue-500/40 bg-blue-500/10 px-2.5 py-1.5 text-[11px] font-medium text-blue-700 hover:bg-blue-500/20 disabled:opacity-50 sm:w-auto sm:py-1 dark:text-blue-300"
            >
              {pending ? '…' : t('review.merge', 'Fusionner')}
            </button>
            <button
              type="button"
              onClick={onKeepBoth}
              disabled={pending}
              className="w-full rounded-md border border-border bg-muted/30 px-2.5 py-1.5 text-[11px] font-medium text-muted-foreground hover:bg-muted/60 disabled:opacity-50 sm:w-auto sm:py-1"
            >
              {t('review.keepBoth', 'Garder les deux')}
            </button>
          </div>
        </div>
      )}
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
          aria-label={t('review.selectRow', 'Select row')}
          checked={selected}
          onChange={onToggleSelect}
          className="h-3.5 w-3.5 shrink-0 cursor-pointer rounded border-border accent-foreground md:justify-self-center"
        />
        <span className="shrink-0 tabular-nums text-[11px] text-muted-foreground md:text-xs">
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
            onUpdateTransactionCategory={onUpdateTransactionCategory}
          />
        </div>
        <span
          className={`shrink-0 tabular-nums md:text-right ${
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
            title={t('review.markAsReviewed', 'Mark as reviewed')}
          >
            {pending ? '…' : '✓'}
          </button>
          {onLinkAsInternalTransfer && (
            <MarkAsTransferButton
              transactionId={transactionId}
              currentAccountId={accountId}
              amount={amount}
              accountOptions={accountOptions}
              onLinkAsInternalTransfer={onLinkAsInternalTransfer}
            />
          )}
          <button
            type="button"
            onClick={onDelete}
            disabled={pending}
            className="rounded-md border border-destructive/40 bg-destructive/10 px-1.5 py-1 text-[11px] font-medium text-destructive hover:bg-destructive/20 disabled:opacity-50"
            title={t('review.deleteTransaction', 'Delete transaction')}
            aria-label={t('review.deleteTransaction', 'Delete transaction')}
          >
            🗑
          </button>
        </div>
      </div>
      </div>
    </div>
  )
}
