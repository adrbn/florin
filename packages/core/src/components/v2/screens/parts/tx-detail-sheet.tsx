'use client'

import { useState, useTransition } from 'react'
import { Check, Pencil, Tags, Trash2 } from 'lucide-react'
import { useRouter } from 'next/navigation'
import { useV2T } from '../../i18n/context'
import { useV2Config } from '../../lib/config'
import { humanizePayee } from '../../lib/format'
import { parseDecimalInput } from '../../../../lib/format/currency'
import { isoDay } from '../../lib/format'
import { Amount } from '../../primitives/amount'
import { Pill } from '../../primitives/atoms'
import { Segmented } from '../../primitives/segmented'
import { Sheet } from '../../primitives/sheet'
import type { V2Tx } from '../../types'
import { cn } from '../../../../lib/utils'

export interface TxDetailActions {
  updateTransactionCategory: (id: string, categoryId: string | null) => Promise<unknown>
  softDeleteTransaction: (id: string) => Promise<unknown>
  approveTransaction: (id: string) => Promise<unknown>
  /** Correct the date, amount, payee or note of an existing row. */
  updateTransaction?: (
    id: string,
    input: { occurredAt?: Date; amount?: number; payee?: string; memo?: string | null },
  ) => Promise<unknown>
}

export function TxDetailSheet({
  tx,
  onClose,
  onCategorize,
  actions,
}: {
  tx: V2Tx | null
  onClose: () => void
  onCategorize: () => void
  actions: TxDetailActions
}) {
  const t = useV2T()
  const { tag } = useV2Config()
  const router = useRouter()
  const [pending, start] = useTransition()
  const [editing, setEditing] = useState(false)

  // Reopening on another row must not land in the previous row's edit form.
  const [seen, setSeen] = useState<string | null>(null)
  if (tx && seen !== tx.id) {
    setSeen(tx.id)
    if (editing) setEditing(false)
  }

  const run = (fn: () => Promise<unknown>) =>
    start(async () => {
      await fn()
      router.refresh()
      onClose()
    })

  return (
    <Sheet open={tx !== null} onClose={onClose} title={tx ? humanizePayee(tx.payee) : undefined}>
      {tx && (
        <div className="v2-gutter flex flex-col gap-5 pt-1">
          <div className="flex flex-col items-center gap-1.5 py-2">
            <Amount
              value={tx.amount}
              signed
              tone="auto"
              className="text-[40px] font-light leading-none"
            />
            <span className="v2-sub">
              {new Intl.DateTimeFormat(tag, { dateStyle: 'full' }).format(new Date(tx.date))}
            </span>
            <div className="mt-1 flex flex-wrap justify-center gap-2">
              <Pill>{tx.accountName}</Pill>
              <Pill tone={tx.categoryName ? 'neutral' : 'warn'}>
                {tx.categoryEmoji ? `${tx.categoryEmoji} ` : ''}
                {tx.categoryName ?? t('v2.common.uncategorized', 'Uncategorized')}
              </Pill>
              {tx.isTransfer && <Pill tone="accent">{t('v2.common.transfer', 'Transfer')}</Pill>}
              {tx.needsReview && (
                <Pill tone="negative">{t('v2.activity.needsReview', 'To review')}</Pill>
              )}
            </div>
          </div>

          {tx.memo && (
            <p className="v2-inset v2-sub p-3.5">{tx.memo}</p>
          )}

          {editing && actions.updateTransaction ? (
            <EditForm
              tx={tx}
              onCancel={() => setEditing(false)}
              onSave={async (input) => {
                await actions.updateTransaction?.(tx.id, input)
                setEditing(false)
              }}
              onDone={() => {
                router.refresh()
                onClose()
              }}
            />
          ) : (
          <div className="flex flex-col gap-2.5 pb-2">
            {/*
              * "Vérifié" leads and carries the accent: on a row that is waiting
              * for review, confirming it is the thing you came to do, and
              * categorising is the occasional correction. The previous order
              * had the rare action dressed as the primary one.
              */}
            {tx.needsReview && (
              <button
                type="button"
                disabled={pending}
                onClick={() => run(() => actions.approveTransaction(tx.id))}
                className="v2-btn v2-btn-primary w-full"
              >
                <Check className="h-4 w-4" />
                {t('v2.activity.markReviewed', 'Vérifié')}
              </button>
            )}
            <button
              type="button"
              disabled={pending}
              onClick={onCategorize}
              className={cn('v2-btn w-full', tx.needsReview ? 'v2-btn-soft' : 'v2-btn-primary')}
            >
              <Tags className="h-4 w-4" />
              {t('v2.activity.categorize', 'Catégoriser')}
            </button>
            {actions.updateTransaction && (
              <button
                type="button"
                disabled={pending}
                onClick={() => setEditing(true)}
                className="v2-btn v2-btn-soft w-full"
              >
                <Pencil className="h-4 w-4" />
                {t('v2.common.edit', 'Modifier')}
              </button>
            )}
            <button
              type="button"
              disabled={pending}
              onClick={() => run(() => actions.softDeleteTransaction(tx.id))}
              className="v2-btn v2-btn-danger w-full"
            >
              <Trash2 className="h-4 w-4" />
              {t('v2.common.delete', 'Supprimer')}
            </button>
          </div>
          )}
        </div>
      )}
    </Sheet>
  )
}


/// Inline correction form.
///
/// Bank feeds get dates and payees wrong often enough that a phone needs this;
/// the fields are exactly the ones `updateTransaction` accepts, so nothing here
/// can silently fail to persist.
function EditForm({
  tx,
  onCancel,
  onSave,
  onDone,
}: {
  tx: V2Tx
  onCancel: () => void
  onSave: (input: {
    occurredAt?: Date
    amount?: number
    payee?: string
    memo?: string | null
  }) => Promise<void>
  onDone: () => void
}) {
  const t = useV2T()
  const [pending, start] = useTransition()
  const [payee, setPayee] = useState(tx.payee)
  const [amount, setAmount] = useState(String(Math.abs(tx.amount)))
  const [isExpense, setIsExpense] = useState(tx.amount < 0)
  const [date, setDate] = useState(isoDay(new Date(tx.date)))
  const [memo, setMemo] = useState(tx.memo ?? '')

  const magnitude = parseDecimalInput(amount, 0)
  const valid = magnitude > 0 && payee.trim().length > 0

  return (
    <div className="flex flex-col gap-4 pb-4">
      <Segmented
        value={isExpense ? 'expense' : 'income'}
        onChange={(v) => setIsExpense(v === 'expense')}
        options={[
          { value: 'expense', label: t('v2.add.expense', 'Dépense') },
          { value: 'income', label: t('v2.add.income', 'Entrée') },
        ]}
      />

      <label className="flex flex-col gap-1.5">
        <span className="v2-eyebrow">{t('v2.add.amount', 'Montant')}</span>
        <input
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          inputMode="decimal"
          className="v2-input v2-num text-[20px]"
        />
      </label>

      <label className="flex flex-col gap-1.5">
        <span className="v2-eyebrow">{t('v2.add.payee', 'Bénéficiaire')}</span>
        <input value={payee} onChange={(e) => setPayee(e.target.value)} className="v2-input" />
      </label>

      <div className="grid grid-cols-2 gap-3">
        <label className="flex flex-col gap-1.5">
          <span className="v2-eyebrow">{t('v2.add.date', 'Date')}</span>
          <input
            type="date"
            value={date}
            onChange={(e) => setDate(e.target.value)}
            className="v2-input"
          />
        </label>
        <label className="flex flex-col gap-1.5">
          <span className="v2-eyebrow">{t('v2.add.memo', 'Note')}</span>
          <input value={memo} onChange={(e) => setMemo(e.target.value)} className="v2-input" />
        </label>
      </div>

      <div className="flex gap-3">
        <button type="button" onClick={onCancel} className="v2-btn v2-btn-soft flex-1">
          {t('v2.common.cancel', 'Annuler')}
        </button>
        <button
          type="button"
          disabled={!valid || pending}
          onClick={() =>
            start(async () => {
              await onSave({
                occurredAt: new Date(`${date}T12:00:00`),
                // The direction toggle owns the sign, here as in the add sheet.
                amount: isExpense ? -Math.abs(magnitude) : Math.abs(magnitude),
                payee: payee.trim(),
                memo: memo.trim() || null,
              })
              onDone()
            })
          }
          className="v2-btn v2-btn-primary flex-1"
        >
          {pending ? t('v2.common.saving', 'Enregistrement…') : t('v2.common.save', 'Enregistrer')}
        </button>
      </div>
    </div>
  )
}
