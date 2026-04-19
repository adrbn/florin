'use client'

import { useState, useTransition } from 'react'
import { Button } from '../ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '../ui/dialog'
import { Input } from '../ui/input'
import { Label } from '../ui/label'
import { useT } from '../../i18n/context'
import type { ActionResult, AddTransactionInput } from '../../types/index'

interface AccountOption {
  id: string
  name: string
}

interface CategoryOption {
  id: string
  name: string
  emoji: string | null
}

interface AddTransactionModalProps {
  accounts: ReadonlyArray<AccountOption>
  categories: ReadonlyArray<CategoryOption>
  /** Pre-select an account in the dropdown — used by the account detail page. */
  defaultAccountId?: string
  /** Optional override for the trigger button label. */
  triggerLabel?: string
  onAddTransaction: (input: AddTransactionInput) => Promise<ActionResult<{ id: string }>>
}

export function AddTransactionModal({
  accounts,
  categories,
  defaultAccountId,
  triggerLabel,
  onAddTransaction,
}: AddTransactionModalProps) {
  const t = useT()
  const resolvedTriggerLabel = triggerLabel ?? t('transactions.add', 'Add transaction')
  const [open, setOpen] = useState(false)
  const [pending, startTransition] = useTransition()
  const [error, setError] = useState<string | null>(null)

  const today = new Date().toISOString().slice(0, 10)

  const onSubmit = (formData: FormData) => {
    setError(null)
    const input: AddTransactionInput = {
      accountId: String(formData.get('accountId') ?? ''),
      occurredAt: new Date(String(formData.get('occurredAt') ?? today)),
      amount: Number(formData.get('amount') ?? 0),
      payee: String(formData.get('payee') ?? ''),
      memo: String(formData.get('memo') ?? '') || null,
      categoryId: String(formData.get('categoryId') ?? '') || null,
    }

    startTransition(async () => {
      const result = await onAddTransaction(input)
      if (!result.success) {
        setError(result.error ?? t('txAdd.unknownError', 'Unknown error'))
        return
      }
      setOpen(false)
      const form = document.getElementById('add-transaction-form') as HTMLFormElement | null
      form?.reset()
    })
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger
        render={
          <Button>
            <span>{resolvedTriggerLabel}</span>
          </Button>
        }
      />
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>{t('txAdd.title', 'New transaction')}</DialogTitle>
          <DialogDescription>
            {t('txAdd.description', 'Negative amount = expense, positive = income.')}
          </DialogDescription>
        </DialogHeader>

        <form id="add-transaction-form" action={onSubmit} className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="accountId">{t('txAdd.account', 'Account')}</Label>
            <select
              id="accountId"
              name="accountId"
              required
              defaultValue={defaultAccountId ?? accounts[0]?.id ?? ''}
              className="flex h-9 w-full rounded-md border border-input bg-transparent px-3 py-1 text-sm shadow-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
            >
              {accounts.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.name}
                </option>
              ))}
            </select>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label htmlFor="occurredAt">{t('txAdd.date', 'Date')}</Label>
              <Input id="occurredAt" name="occurredAt" type="date" defaultValue={today} required />
            </div>
            <div className="space-y-2">
              <Label htmlFor="amount">{t('txAdd.amount', 'Amount (EUR)')}</Label>
              <Input
                id="amount"
                name="amount"
                type="number"
                step="0.01"
                placeholder={t('txAdd.amountPlaceholder', '-12.34')}
                required
              />
            </div>
          </div>

          <div className="space-y-2">
            <Label htmlFor="payee">{t('txAdd.payee', 'Payee')}</Label>
            <Input id="payee" name="payee" required maxLength={200} />
          </div>

          <div className="space-y-2">
            <Label htmlFor="categoryId">{t('txAdd.category', 'Category')}</Label>
            <select
              id="categoryId"
              name="categoryId"
              defaultValue=""
              className="flex h-9 w-full rounded-md border border-input bg-transparent px-3 py-1 text-sm shadow-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
            >
              <option value="">{t('txAdd.categoryAuto', '— Auto —')}</option>
              {categories.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.emoji ? `${c.emoji} ` : ''}
                  {c.name}
                </option>
              ))}
            </select>
          </div>

          <div className="space-y-2">
            <Label htmlFor="memo">{t('txAdd.memo', 'Memo (optional)')}</Label>
            <Input id="memo" name="memo" maxLength={500} />
          </div>

          {error && <p className="text-sm text-destructive">{error}</p>}

          <Button type="submit" disabled={pending} className="w-full">
            {pending ? t('txAdd.submitting', 'Saving…') : t('txAdd.submit', 'Save transaction')}
          </Button>
        </form>
      </DialogContent>
    </Dialog>
  )
}
