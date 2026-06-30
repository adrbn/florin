'use client'

import { useRef, useState, useTransition } from 'react'
import { ArrowLeftRight, Repeat } from 'lucide-react'
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
  TransactionRecurringInput,
} from '../../types/index'

interface AccountOption {
  id: string
  name: string
  currentBalance: number
}

const LIVRET_A_PATTERN = /livret\s*a\b/i

function pickDefaultToAccount(
  accounts: ReadonlyArray<AccountOption>,
  fromId: string,
): string {
  const livretA = accounts.find(
    (a) => LIVRET_A_PATTERN.test(a.name) && a.id !== fromId,
  )
  if (livretA) return livretA.id
  return accounts.find((a) => a.id !== fromId)?.id ?? ''
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
  const [balanceWarning, setBalanceWarning] = useState<string | null>(null)
  // Transfer-only: "Répéter chaque mois" toggle (Phase 1 DCA use case). When on,
  // the bound action spawns a monthly recurring rule and materializes forecast legs.
  const [recurring, setRecurring] = useState(false)
  const [recurrenceDay, setRecurrenceDay] = useState<number>(
    () => new Date().getDate(),
  )
  const fromAccountRef = useRef<HTMLSelectElement>(null)
  const toAccountRef = useRef<HTMLSelectElement>(null)
  // Tracks the last form payload the user tried to submit but was warned
  // about (insufficient balance). When non-null, the submit button becomes
  // "Save anyway" and a second click proceeds with this payload.
  const pendingTransferRef = useRef<AddTransferInput | null>(null)

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

  const submitTransfer = (input: AddTransferInput) => {
    if (!onAddTransfer) return
    startTransition(async () => {
      const result = await onAddTransfer(input)
      if (!result.success) {
        setError(result.error ?? t('txAdd.unknownError', 'Unknown error'))
        return
      }
      setOpen(false)
      pendingTransferRef.current = null
      setBalanceWarning(null)
      setRecurring(false)
      const form = document.getElementById(
        'add-transaction-form',
      ) as HTMLFormElement | null
      form?.reset()
    })
  }

  const onSubmit = (formData: FormData) => {
    setError(null)
    if (mode === 'transfer' && onAddTransfer) {
      const fromAccountId = String(formData.get('fromAccountId') ?? '')
      const toAccountId = String(formData.get('toAccountId') ?? '')
      if (fromAccountId === toAccountId) {
        setError(t('txAdd.transferSameAccount', 'Source and destination must differ.'))
        return
      }
      const recurringInput: TransactionRecurringInput | null = recurring
        ? {
            frequency: 'monthly',
            dayOfMonth: Math.min(31, Math.max(1, Math.trunc(recurrenceDay) || 1)),
          }
        : null
      const input: AddTransferInput = {
        fromAccountId,
        toAccountId,
        amount: Math.abs(Number(formData.get('amount') ?? 0)),
        occurredAt: new Date(String(formData.get('occurredAt') ?? today)),
        memo: String(formData.get('memo') ?? '') || null,
        recurring: recurringInput,
      }

      // If user already acknowledged the warning for this exact payload,
      // let it through.
      const acknowledged =
        pendingTransferRef.current &&
        pendingTransferRef.current.fromAccountId === input.fromAccountId &&
        pendingTransferRef.current.toAccountId === input.toAccountId &&
        pendingTransferRef.current.amount === input.amount

      if (!acknowledged) {
        const source = accounts.find((a) => a.id === fromAccountId)
        if (source && input.amount > source.currentBalance) {
          pendingTransferRef.current = input
          setBalanceWarning(
            t(
              'txAdd.insufficientBalance',
              'Insufficient balance on {account} ({balance} €). Click "Save anyway" to continue — the balance will go negative.',
            )
              .replace('{account}', source.name)
              .replace('{balance}', source.currentBalance.toFixed(2)),
          )
          return
        }
      }

      submitTransfer(input)
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
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next)
        if (!next) {
          setError(null)
          setBalanceWarning(null)
          pendingTransferRef.current = null
          setRecurring(false)
        }
      }}
    >
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
                setBalanceWarning(null)
                pendingTransferRef.current = null
                setRecurring(false)
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
                setBalanceWarning(null)
                pendingTransferRef.current = null
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
                    defaultValue={pickDefaultToAccount(
                      accounts,
                      defaultAccountId ?? accounts[0]?.id ?? '',
                    )}
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

              <div
                className={cn(
                  'space-y-2 rounded-md border p-3 transition-colors',
                  recurring ? 'border-primary/50 bg-primary/5' : 'border-input bg-muted/20',
                )}
              >
                <label className="flex cursor-pointer items-start gap-2.5 text-sm">
                  <input
                    type="checkbox"
                    checked={recurring}
                    onChange={(e) => setRecurring(e.target.checked)}
                    className="mt-0.5 h-4 w-4 shrink-0 cursor-pointer rounded border-border accent-primary"
                  />
                  <span className="min-w-0">
                    <span className="flex items-center gap-1.5 font-medium text-foreground">
                      <Repeat className="h-3.5 w-3.5 shrink-0 text-primary" />
                      {t('txAdd.makeRecurring', 'Répéter chaque mois')}
                    </span>
                    <span className="mt-0.5 block text-[11px] text-muted-foreground">
                      {t(
                        'txAdd.makeRecurringHint',
                        'Schedule this transfer to repeat automatically every month (e.g. recurring savings).',
                      )}
                    </span>
                  </span>
                </label>
                {recurring && (
                  <div className="grid grid-cols-2 gap-3 pt-1">
                    <div className="space-y-1.5">
                      <Label className="text-xs text-muted-foreground">
                        {t('txAdd.recurrenceFrequency', 'Frequency')}
                      </Label>
                      <p className="flex h-9 items-center rounded-md border border-input bg-muted/30 px-3 text-sm text-muted-foreground">
                        {t('txAdd.frequencyMonthly', 'Monthly')}
                      </p>
                    </div>
                    <div className="space-y-1.5">
                      <Label htmlFor="recurrenceDay" className="text-xs text-muted-foreground">
                        {t('txAdd.recurrenceDay', { n: recurrenceDay }, 'On day {n} of the month')}
                      </Label>
                      <Input
                        id="recurrenceDay"
                        type="number"
                        min={1}
                        max={31}
                        step={1}
                        value={recurrenceDay}
                        onChange={(e) => {
                          const n = Number(e.target.value)
                          if (Number.isFinite(n)) setRecurrenceDay(Math.min(31, Math.max(1, Math.trunc(n))))
                        }}
                      />
                    </div>
                  </div>
                )}
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
          {balanceWarning && (
            <p className="text-sm text-amber-600 dark:text-amber-400">{balanceWarning}</p>
          )}

          <Button type="submit" disabled={pending} className="w-full">
            {pending
              ? t('txAdd.submitting', 'Saving…')
              : mode === 'transfer'
                ? balanceWarning
                  ? t('txAdd.submitTransferAnyway', 'Save anyway')
                  : t('txAdd.submitTransfer', 'Save transfer')
                : t('txAdd.submit', 'Save transaction')}
          </Button>
        </form>
      </DialogContent>
    </Dialog>
  )
}
