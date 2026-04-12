'use client'

import { useTransition } from 'react'
import type { ActionResult } from '../../types/index'

interface DeleteTransactionButtonProps {
  transactionId: string
  payee: string
  onSoftDeleteTransaction: (id: string) => Promise<ActionResult>
}

/**
 * Small client-side trash button used on server-rendered transaction
 * tables. Keeps the parent server component green while still letting the
 * user soft-delete one row with a confirm prompt.
 */
export function DeleteTransactionButton({ transactionId, payee, onSoftDeleteTransaction }: DeleteTransactionButtonProps) {
  const [pending, startTransition] = useTransition()
  const onDelete = () => {
    const ok = window.confirm(`Delete "${payee}"?`)
    if (!ok) return
    startTransition(async () => {
      await onSoftDeleteTransaction(transactionId)
    })
  }
  return (
    <button
      type="button"
      onClick={onDelete}
      disabled={pending}
      className="rounded-md border border-destructive/40 bg-destructive/10 px-1.5 py-0.5 text-[11px] font-medium text-destructive hover:bg-destructive/20 disabled:opacity-50"
      title="Delete transaction"
      aria-label="Delete transaction"
    >
      {pending ? '…' : '🗑'}
    </button>
  )
}
