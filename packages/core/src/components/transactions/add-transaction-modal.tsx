'use client'

import { useRef, useState, useTransition } from 'react'
import { ArrowLeftRight } from 'lucide-react'
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
import { cn } from '../../lib/utils'
import type {
  ActionResult,
  AddTransactionInput,
  AddTransferInput,
} from '../../types/index'

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
  /** Optional — when provided, the modal offers a "transfer" mode. */
  onAddTransfer?: (
    input: AddTransferInput,
  ) => Promise<ActionResult<{ transferPairId: string }>>
}

type Mode = 'transaction' | 'transfer'

export function AddTransactionModal({
  accounts,
  categories,
  defaultAccountId,
  triggerLabel,
  onAddTransaction,
  onAddTransfer,
}: AddTransactionModalProps) {
  const t = useT()
  const resolvedTriggerLabel = triggerLabel ?? t('transactions.add', 'Add transaction')
  const [open, setOpen] = useState(false)
  const [mode, setMode] = useState<Mode>('transaction')
  const [pending, startTransition] = useTransition()
  const [error, setError] = useState<string | null>(null)
  const fromAccountRef = useRef<HTMLSelectElement>(null)
  const toAccountRef = useRef<HTMLSelectElement>(null)

  // Swap the two select values without touching state — the form is
  // uncontrolled and reads via FormData, so a direct DOM swap is enough.
  const swapTransferAccounts = () => {
    const fromEl = fromAccountRef.current
    const toEl = toAccountRef.current
    if (!fromEl || !toEl) return
    const tmp = fromEl.value
    fromEl.value = toEl.value
    toEl.value = tmp
  }

  const today = new Date().toISOString().slice(0, 10)
  const canTransfer = Boolean(onAddTransfer) && accounts.length >= 2

  const onSubmit = (formData: FormData) => {
    setError(null)
    if (mode === 'transfer' && onAddTransfer) {
      const fromAccountId = String(formData.get('fromAccountId') ?? '')
      const toAccountId = String(formData.get('toAccountId') ?? '')
      if (fromAccountId === toAccountId) {
        setError(t('txAdd.transferSameAccount', 'Source and destination must differ.'))
        return
      }
      const input: AddTransferInput = {
        fromAccountId,
        toAccountId,
        amount: Math.abs(Number(formData.get('amount') ?? 0)),
        occurredAt: new Date(String(formData.get('occurredAt') ?? today)),
        memo: String(formData.get('memo') ?? '') || null,
      }
      startTransition(async () => {
        const result = await onAddTransfer(input)
        if (!result.success) {
          setError(result.error ?? t('txAdd.unknownError', 'Unknown error'))
          return
        }
        setOpen(false)
        const form = document.getElementById(
          'add-transaction-form',
        ) as HTMLFormElement | null
        form?.reset()
      })
      return
    }

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

  const selectClass =
    'flex h-9 w-full rounded-md border border-input bg-transparent px-3 py-1 text-sm shadow-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring'

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
          <DialogTitle>
            {mode === 'transfer'
              ? t('txAdd.transferTitle', 'New transfer')
              : t('txAdd.title', 'New transaction')}
          </DialogTitle>
          <DialogDescription>
            {mode === 'transfer'
              ? t(
                  'txAdd.transferDescription',
                  'Move money between your own accounts. Excluded from income and burn.',
                )
              : t('txAdd.description', 'Negative amount = expense, positive = income.')}
          </DialogDescription>
        </DialogHeader>

        {canTransfer ? (
          <div
            role="tablist"
            className="inline-flex rounded-md border border-input p-0.5 text-xs self-start"
          >
            <button
              type="button"
              role="tab"
              aria-selected={mode === 'transaction'}
              onClick={() => {
                setMode('transaction')
                setError(null)
              }}
              className={cn(
                'rounded-sm px-3 py-1.5 transition-colors',
                mode === 'transaction'
                  ? 'bg-primary text-primary-foreground'
                  : 'text-muted-foreground hover:text-foreground',
              )}
            >
              {t('txAdd.modeTransaction', 'Transaction')}
            </button>
            <button
              type="button"
              role="tab"
              aria-selected={mode === 'transfer'}
              onClick={() => {
                setMode('transfer')
                setError(null)
              }}
              className={cn(
                'rounded-sm px-3 py-1.5 transition-colors',
                mode === 'transfer'
                  ? 'bg-primary text-primary-foreground'
                  : 'text-muted-foreground hover:text-foreground',
              )}
            >
              {t('txAdd.modeTransfer', 'Transfer')}
            </button>
          </div>
        ) : null}

        <form id="add-transaction-form" action={onSubmit} className="space-y-4">
          {mode === 'transfer' ? (
            <>
              <div className="grid grid-cols-[1fr_auto_1fr] items-end gap-3">
                <div className="space-y-2">
                  <Label htmlFor="fromAccountId">{t('txAdd.fromAccount', 'From')}</Label>
                  <select
                    id="fromAccountId"
                    name="fromAccountId"
                    required
                    ref={fromAccountRef}
                    defaultValue={defaultAccountId ?? accounts[0]?.id ?? ''}
                    className={selectClass}
                  >
                    {accounts.map((a) => (
                      <option key={a.id} value={a.id}>
                        {a.name}
                      </option>
                    ))}
                  </select>
                </div>
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  onClick={swapTransferAccounts}
                  aria-label={t('txAdd.swapAccounts', 'Swap accounts')}
                  title={t('txAdd.swapAccounts', 'Swap accounts')}
                  className="mb-0.5 h-9 w-9 shrink-0 p-0"
                >
                  <ArrowLeftRight className="h-4 w-4" />
                </Button>
                <div className="space-y-2">
                  <Label htmlFor="toAccountId">{t('txAdd.toAccount', 'To')}</Label>
                  <select
                    id="toAccountId"
                    name="toAccountId"
                    required
                    ref={toAccountRef}
                    defaultValue={
                      accounts.find((a) => a.id !== (defaultAccountId ?? accounts[0]?.id))?.id ??
                      ''
                    }
                    className={selectClass}
                  >
                    {accounts.map((a) => (
                      <option key={a.id} value={a.id}>
                        {a.name}
                      </option>
                    ))}
                  </select>
                </div>
              </div>
            </>
          ) : (
            <div className="space-y-2">
              <Label htmlFor="accountId">{t('txAdd.account', 'Account')}</Label>
              <select
                id="accountId"
                name="accountId"
                required
                defaultValue={defaultAccountId ?? accounts[0]?.id ?? ''}
                className={selectClass}
              >
                {accounts.map((a) => (
                  <option key={a.id} value={a.id}>
                    {a.name}
                  </option>
                ))}
              </select>
            </div>
          )}

          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-2">
              <Label htmlFor="occurredAt">{t('txAdd.date', 'Date')}</Label>
              <Input id="occurredAt" name="occurredAt" type="date" defaultValue={today} required />
            </div>
            <div className="space-y-2">
              <Label htmlFor="amount">
                {mode === 'transfer'
                  ? t('txAdd.transferAmount', 'Amount (EUR)')
                  : t('txAdd.amount', 'Amount (EUR)')}
              </Label>
              <Input
                id="amount"
                name="amount"
                type="number"
                step="0.01"
                min={mode === 'transfer' ? '0.01' : undefined}
                placeholder={
                  mode === 'transfer' ? '100.00' : t('txAdd.amountPlaceholder', '-12.34')
                }
                required
              />
            </div>
          </div>

          {mode === 'transaction' ? (
            <>
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
                  className={selectClass}
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
            </>
          ) : null}

          <div className="space-y-2">
            <Label htmlFor="memo">{t('txAdd.memo', 'Memo (optional)')}</Label>
            <Input id="memo" name="memo" maxLength={500} />
          </div>

          {error && <p className="text-sm text-destructive">{error}</p>}

          <Button type="submit" disabled={pending} className="w-full">
            {pending
              ? t('txAdd.submitting', 'Saving…')
              : mode === 'transfer'
                ? t('txAdd.submitTransfer', 'Save transfer')
                : t('txAdd.submit', 'Save transaction')}
          </Button>
        </form>
      </DialogContent>
    </Dialog>
  )
}
