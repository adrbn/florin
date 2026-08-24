'use client'

import { useMemo, useState, useTransition } from 'react'
import { ArrowLeftRight, Check, RefreshCw, TrendingDown, TrendingUp } from 'lucide-react'
import { useRouter } from 'next/navigation'
import { parseDecimalInput } from '../../../lib/format/currency'
import { useV2T } from '../i18n/context'
import { useV2Config } from '../lib/config'
import { isoDay } from '../lib/format'
import { Segmented } from '../primitives/segmented'
import { Sheet } from '../primitives/sheet'
import type { V2Account, V2AddActions, V2Category } from '../types'
import { cn } from '../../../lib/utils'

type Mode = 'tx' | 'transfer' | 'sync'
type Direction = 'expense' | 'income'

/**
 * The centre-button sheet: record a transaction, move money between accounts,
 * or pull the banks. Three jobs, one surface — every neobank puts them here
 * and it saves three screens.
 */
export function QuickAddSheet({
  open,
  onClose,
  accounts,
  categories,
  actions,
}: {
  open: boolean
  onClose: () => void
  accounts: V2Account[]
  categories: V2Category[]
  actions: V2AddActions
}) {
  const t = useV2T()
  const [mode, setMode] = useState<Mode>('tx')

  return (
    <Sheet open={open} onClose={onClose} title={t('v2.add.title', 'Add')}>
      <div className="v2-gutter flex flex-col gap-5 pt-1">
        <Segmented
          value={mode}
          onChange={setMode}
          options={[
            { value: 'tx', label: t('v2.add.transaction', 'Transaction') },
            { value: 'transfer', label: t('v2.add.transfer', 'Transfer') },
            { value: 'sync', label: t('v2.add.syncShort', 'Sync') },
          ]}
        />
        {mode === 'tx' && (
          <TxForm accounts={accounts} categories={categories} actions={actions} onDone={onClose} />
        )}
        {mode === 'transfer' && (
          <TransferForm accounts={accounts} actions={actions} onDone={onClose} />
        )}
        {mode === 'sync' && <SyncPanel actions={actions} />}
      </div>
    </Sheet>
  )
}

// ------------------------------------------------------------------ amount

/**
 * The amount field is the hero of this sheet, so it gets hero treatment: 44px,
 * centred, no box. `inputMode="decimal"` brings up the numeric keypad with a
 * separator key, which `type="number"` does not do reliably on iOS.
 */
function AmountField({
  value,
  onChange,
  tone,
}: {
  value: string
  onChange: (v: string) => void
  tone: 'positive' | 'negative'
}) {
  const { currency, tag } = useV2Config()
  const symbol = useMemo(() => {
    const part = new Intl.NumberFormat(tag, { style: 'currency', currency })
      .formatToParts(0)
      .find((p) => p.type === 'currency')
    return part?.value ?? currency
  }, [tag, currency])

  return (
    <div className="flex items-baseline justify-center gap-1.5 py-2">
      <input
        value={value}
        onChange={(e) => onChange(e.target.value)}
        inputMode="decimal"
        autoComplete="off"
        placeholder="0"
        aria-label="Amount"
        className={cn(
          'v2-num w-[min(62vw,240px)] bg-transparent text-center text-[44px] font-light leading-none tracking-[-0.04em] outline-none placeholder:text-[var(--v2-text-3)]',
          tone === 'positive' ? 'text-[var(--v2-pos)]' : 'text-[var(--v2-text)]',
        )}
      />
      <span className="text-[20px] font-light text-[var(--v2-text-3)]">{symbol}</span>
    </div>
  )
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="flex flex-col gap-1.5">
      <span className="v2-eyebrow">{label}</span>
      {children}
    </label>
  )
}

function Feedback({ error }: { error: string | null }) {
  if (!error) return null
  return (
    <p role="alert" className="text-[12.5px] text-[var(--v2-neg)]">
      {error}
    </p>
  )
}

// ------------------------------------------------------------- transaction

function TxForm({
  accounts,
  categories,
  actions,
  onDone,
}: {
  accounts: V2Account[]
  categories: V2Category[]
  actions: V2AddActions
  onDone: () => void
}) {
  const t = useV2T()
  const router = useRouter()
  const [pending, start] = useTransition()
  const [error, setError] = useState<string | null>(null)

  const usable = accounts.filter((a) => !a.isArchived && a.kind !== 'loan')
  const [direction, setDirection] = useState<Direction>('expense')
  const [amount, setAmount] = useState('')
  const [payee, setPayee] = useState('')
  const [accountId, setAccountId] = useState(usable[0]?.id ?? '')
  const [categoryId, setCategoryId] = useState('')
  const [date, setDate] = useState(isoDay(new Date()))
  const [memo, setMemo] = useState('')

  const magnitude = parseDecimalInput(amount, 0)
  const valid = magnitude > 0 && payee.trim().length > 0 && accountId !== ''

  const submit = () => {
    if (!valid || pending) return
    setError(null)
    start(async () => {
      const res = await actions.addTransaction({
        accountId,
        occurredAt: new Date(`${date}T12:00:00`),
        // Expenses are stored negative; the direction toggle is the only place
        // the user should ever have to think about the sign.
        amount: direction === 'expense' ? -Math.abs(magnitude) : Math.abs(magnitude),
        payee: payee.trim(),
        memo: memo.trim() || null,
        categoryId: categoryId || null,
      })
      if (!res.success) {
        setError(res.error ?? t('v2.common.error', 'Something went wrong'))
        return
      }
      router.refresh()
      onDone()
    })
  }

  return (
    <div className="flex flex-col gap-4 pb-4">
      <Segmented
        value={direction}
        onChange={setDirection}
        options={[
          { value: 'expense', label: t('v2.add.expense', 'Expense') },
          { value: 'income', label: t('v2.add.income', 'Income') },
        ]}
      />

      <AmountField
        value={amount}
        onChange={setAmount}
        tone={direction === 'income' ? 'positive' : 'negative'}
      />

      <Field label={t('v2.add.payee', 'Payee')}>
        <input
          value={payee}
          onChange={(e) => setPayee(e.target.value)}
          className="v2-input"
          autoComplete="off"
        />
      </Field>

      <div className="grid grid-cols-2 gap-3">
        <Field label={t('v2.add.account', 'Account')}>
          <select
            value={accountId}
            onChange={(e) => setAccountId(e.target.value)}
            className="v2-input"
          >
            {usable.map((a) => (
              <option key={a.id} value={a.id}>
                {a.name}
              </option>
            ))}
          </select>
        </Field>
        <Field label={t('v2.add.date', 'Date')}>
          <input
            type="date"
            value={date}
            onChange={(e) => setDate(e.target.value)}
            className="v2-input"
          />
        </Field>
      </div>

      <Field label={t('v2.add.category', 'Category')}>
        <select
          value={categoryId}
          onChange={(e) => setCategoryId(e.target.value)}
          className="v2-input"
        >
          <option value="">{t('v2.common.uncategorized', 'Uncategorized')}</option>
          {categories.map((c) => (
            <option key={c.id} value={c.id}>
              {c.emoji ? `${c.emoji} ` : ''}
              {c.name} · {c.groupName}
            </option>
          ))}
        </select>
      </Field>

      <Field label={t('v2.add.memo', 'Note')}>
        <input value={memo} onChange={(e) => setMemo(e.target.value)} className="v2-input" />
      </Field>

      <Feedback error={error} />

      <button
        type="button"
        disabled={!valid || pending}
        onClick={submit}
        className="v2-btn v2-btn-primary w-full"
      >
        {pending ? (
          t('v2.common.saving', 'Saving…')
        ) : (
          <>
            <Check className="h-4 w-4" />
            {t('v2.common.save', 'Save')}
          </>
        )}
      </button>
    </div>
  )
}

// ---------------------------------------------------------------- transfer

function TransferForm({
  accounts,
  actions,
  onDone,
}: {
  accounts: V2Account[]
  actions: V2AddActions
  onDone: () => void
}) {
  const t = useV2T()
  const router = useRouter()
  const [pending, start] = useTransition()
  const [error, setError] = useState<string | null>(null)

  const usable = accounts.filter((a) => !a.isArchived)
  const [amount, setAmount] = useState('')
  const [fromId, setFromId] = useState(usable[0]?.id ?? '')
  const [toId, setToId] = useState(usable[1]?.id ?? usable[0]?.id ?? '')
  const [date, setDate] = useState(isoDay(new Date()))
  const [memo, setMemo] = useState('')

  const magnitude = parseDecimalInput(amount, 0)
  const valid = magnitude > 0 && fromId !== '' && toId !== '' && fromId !== toId

  const swap = () => {
    setFromId(toId)
    setToId(fromId)
  }

  const submit = () => {
    if (!valid || pending) return
    setError(null)
    start(async () => {
      const res = await actions.addTransfer({
        fromAccountId: fromId,
        toAccountId: toId,
        amount: Math.abs(magnitude),
        occurredAt: new Date(`${date}T12:00:00`),
        memo: memo.trim() || null,
      })
      if (!res.success) {
        setError(res.error ?? t('v2.common.error', 'Something went wrong'))
        return
      }
      router.refresh()
      onDone()
    })
  }

  return (
    <div className="flex flex-col gap-4 pb-4">
      <AmountField value={amount} onChange={setAmount} tone="negative" />

      <div className="flex items-end gap-2">
        <div className="min-w-0 flex-1">
          <Field label={t('v2.add.from', 'From')}>
            <select
              value={fromId}
              onChange={(e) => setFromId(e.target.value)}
              className="v2-input"
            >
              {usable.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.name}
                </option>
              ))}
            </select>
          </Field>
        </div>
        <button
          type="button"
          onClick={swap}
          aria-label="Swap"
          className="v2-iconbtn mb-[5px] h-[46px] w-[46px] rounded-[var(--v2-r-md)]"
        >
          <ArrowLeftRight className="h-4 w-4" />
        </button>
        <div className="min-w-0 flex-1">
          <Field label={t('v2.add.to', 'To')}>
            <select value={toId} onChange={(e) => setToId(e.target.value)} className="v2-input">
              {usable.map((a) => (
                <option key={a.id} value={a.id}>
                  {a.name}
                </option>
              ))}
            </select>
          </Field>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-3">
        <Field label={t('v2.add.date', 'Date')}>
          <input
            type="date"
            value={date}
            onChange={(e) => setDate(e.target.value)}
            className="v2-input"
          />
        </Field>
        <Field label={t('v2.add.memo', 'Note')}>
          <input value={memo} onChange={(e) => setMemo(e.target.value)} className="v2-input" />
        </Field>
      </div>

      <Feedback error={error} />

      <button
        type="button"
        disabled={!valid || pending}
        onClick={submit}
        className="v2-btn v2-btn-primary w-full"
      >
        {pending ? t('v2.common.saving', 'Saving…') : t('v2.common.save', 'Save')}
      </button>
    </div>
  )
}

// -------------------------------------------------------------------- sync

function SyncPanel({ actions }: { actions: V2AddActions }) {
  const t = useV2T()
  const router = useRouter()
  const [pending, start] = useTransition()
  const [result, setResult] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  const run = () => {
    setError(null)
    setResult(null)
    start(async () => {
      const res = await actions.syncAllBanks()
      if (!res.success) {
        setError(res.error ?? t('v2.overview.syncFailed', 'Sync failed'))
        return
      }
      const d = res.data
      setResult(
        d
          ? `${d.connectionsSynced} · ${d.accountsSynced} · +${d.transactionsInserted}`
          : t('v2.overview.synced', 'Up to date'),
      )
      router.refresh()
    })
  }

  return (
    <div className="flex flex-col gap-4 pb-4">
      <p className="v2-sub">{t('v2.add.syncHint', 'Pull the latest transactions')}</p>
      <button
        type="button"
        onClick={run}
        disabled={pending}
        className="v2-btn v2-btn-primary w-full"
      >
        <RefreshCw className={cn('h-4 w-4', pending && 'animate-spin')} />
        {pending ? t('v2.overview.syncing', 'Syncing…') : t('v2.add.sync', 'Sync banks')}
      </button>
      {result && (
        <p className="v2-num flex items-center gap-2 text-[13px] text-[var(--v2-pos)]">
          <TrendingUp className="h-4 w-4" />
          {result}
        </p>
      )}
      {error && (
        <p role="alert" className="flex items-center gap-2 text-[13px] text-[var(--v2-neg)]">
          <TrendingDown className="h-4 w-4" />
          {error}
        </p>
      )}
    </div>
  )
}
