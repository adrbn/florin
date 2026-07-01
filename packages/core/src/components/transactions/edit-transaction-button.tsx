'use client'

import { useState, useTransition } from 'react'
import { Pencil } from 'lucide-react'
import { Button } from '../ui/button'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '../ui/dialog'
import { Input } from '../ui/input'
import { Label } from '../ui/label'
import { useT } from '../../i18n/context'
import type { ActionResult, UpdateTransactionInput } from '../../types/index'

interface EditTransactionButtonProps {
  transactionId: string
  /** Current date as an ISO `yyyy-mm-dd` string (prefill for the date input). */
  date: string
  /** Current signed amount — negative = expense, positive = income. */
  amount: number
  payee: string
  memo?: string | null
  onUpdateTransaction: (
    id: string,
    input: UpdateTransactionInput,
  ) => Promise<ActionResult>
}

/** Normalize any date-ish value to a `yyyy-mm-dd` string for a `type="date"` input. */
function toDateInputValue(value: string): string {
  // Already `yyyy-mm-dd` (possibly with a time suffix) — keep the date part.
  const isoMatch = /^\d{4}-\d{2}-\d{2}/.exec(value)
  if (isoMatch) return isoMatch[0]
  const parsed = new Date(value)
  if (Number.isNaN(parsed.getTime())) return ''
  return parsed.toISOString().slice(0, 10)
}

/**
 * Small client-side edit button for a single transaction row. Opens a compact
 * dialog to change the date, amount, payee and memo. Only the fields the user
 * actually changed are sent to `onUpdateTransaction`, so the patch stays
 * minimal (primary use: moving a reimbursement onto the original expense day).
 */
export function EditTransactionButton({
  transactionId,
  date,
  amount,
  payee,
  memo,
  onUpdateTransaction,
}: EditTransactionButtonProps) {
  const t = useT()
  const [open, setOpen] = useState(false)
  const [pending, startTransition] = useTransition()
  const [error, setError] = useState<string | null>(null)

  const initialDate = toDateInputValue(date)
  const initialMemo = memo ?? ''

  const onSubmit = (formData: FormData) => {
    setError(null)
    const nextDate = String(formData.get('date') ?? '')
    const nextAmount = String(formData.get('amount') ?? '')
    const nextPayee = String(formData.get('payee') ?? '')
    const nextMemo = String(formData.get('memo') ?? '')

    // Diff against the original so we only send changed fields.
    const input: UpdateTransactionInput = {}
    if (nextDate && nextDate !== initialDate) {
      input.occurredAt = new Date(`${nextDate}T00:00:00`)
    }
    if (nextAmount !== '' && Number(nextAmount) !== amount) {
      input.amount = Number(nextAmount)
    }
    if (nextPayee !== payee) {
      input.payee = nextPayee
    }
    if (nextMemo !== initialMemo) {
      input.memo = nextMemo === '' ? null : nextMemo
    }

    // Nothing changed — just close.
    if (Object.keys(input).length === 0) {
      setOpen(false)
      return
    }

    startTransition(async () => {
      const result = await onUpdateTransaction(transactionId, input)
      if (!result.success) {
        setError(result.error ?? t('txEdit.unknownError', 'Unknown error'))
        return
      }
      setOpen(false)
    })
  }

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next)
        if (!next) setError(null)
      }}
    >
      <Button
        type="button"
        variant="ghost"
        size="icon-xs"
        onClick={() => setOpen(true)}
        title={t('txEdit.edit', 'Edit transaction')}
        aria-label={t('txEdit.edit', 'Edit transaction')}
        className="text-muted-foreground hover:text-foreground"
      >
        <Pencil />
      </Button>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>{t('txEdit.title', 'Edit transaction')}</DialogTitle>
        </DialogHeader>
        <form action={onSubmit} className="space-y-4">
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label htmlFor="edit-tx-date">{t('txEdit.date', 'Date')}</Label>
              <Input
                id="edit-tx-date"
                name="date"
                type="date"
                defaultValue={initialDate}
                required
              />
            </div>
            <div className="space-y-2">
              <Label htmlFor="edit-tx-amount">{t('txEdit.amount', 'Amount (EUR)')}</Label>
              <Input
                id="edit-tx-amount"
                name="amount"
                type="number"
                step="0.01"
                defaultValue={amount}
                required
              />
            </div>
          </div>

          <div className="space-y-2">
            <Label htmlFor="edit-tx-payee">{t('txEdit.payee', 'Payee')}</Label>
            <Input
              id="edit-tx-payee"
              name="payee"
              defaultValue={payee}
              maxLength={200}
              required
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor="edit-tx-memo">{t('txEdit.memo', 'Memo (optional)')}</Label>
            <Input
              id="edit-tx-memo"
              name="memo"
              defaultValue={initialMemo}
              maxLength={500}
            />
          </div>

          {error && <p className="text-sm text-destructive">{error}</p>}

          <div className="flex justify-end gap-2">
            <Button
              type="button"
              variant="outline"
              onClick={() => setOpen(false)}
              disabled={pending}
            >
              {t('common.cancel', 'Cancel')}
            </Button>
            <Button type="submit" disabled={pending}>
              {pending ? t('txEdit.saving', 'Saving…') : t('common.save', 'Save')}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  )
}
