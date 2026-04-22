'use client'

import { useEffect, useRef, useState, useTransition } from 'react'
import { useT } from '../../i18n/context'
import type { ActionResult } from '../../types/index'

export interface AccountOption {
  id: string
  name: string
}

interface MarkAsTransferButtonProps {
  transactionId: string
  /** Account id of the pending transaction — excluded from the picker. */
  currentAccountId: string | null
  /** Sign drives the label: inflow → "Depuis" (from), outflow → "Vers" (to). */
  amount: number
  accountOptions: ReadonlyArray<AccountOption>
  onLinkAsInternalTransfer: (
    transactionId: string,
    counterpartAccountId: string,
  ) => Promise<ActionResult<{ transferPairId: string; mode: 'paired' | 'created' }>>
}

/**
 * Compact ⇄ action on the review row that promotes an imported transaction
 * into an internal-transfer leg. Click reveals an account picker (same lane
 * as the category popover — absolute, z-50). Selecting an account fires the
 * server action which either links an existing opposite-sign row or inserts
 * a synthetic counterpart on the target account.
 *
 * Rendered inside a Card with `overflow-visible`; no portal needed.
 */
export function MarkAsTransferButton({
  transactionId,
  currentAccountId,
  amount,
  accountOptions,
  onLinkAsInternalTransfer,
}: MarkAsTransferButtonProps) {
  const t = useT()
  const [open, setOpen] = useState(false)
  const [pending, startTransition] = useTransition()
  const [error, setError] = useState<string | null>(null)
  const ref = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!open) return
    const onClick = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) {
        setOpen(false)
      }
    }
    document.addEventListener('mousedown', onClick)
    return () => document.removeEventListener('mousedown', onClick)
  }, [open])

  // Dismiss transient error when the popover re-opens.
  useEffect(() => {
    if (open) setError(null)
  }, [open])

  const onPick = (counterpartAccountId: string) => {
    setError(null)
    startTransition(async () => {
      const result = await onLinkAsInternalTransfer(transactionId, counterpartAccountId)
      if (result.success) {
        setOpen(false)
      } else {
        setError(result.error ?? t('review.transferFailed', 'Could not mark as transfer'))
      }
    })
  }

  const eligible = accountOptions.filter((a) => a.id !== currentAccountId)

  return (
    <div ref={ref} className="relative inline-block">
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        disabled={pending || eligible.length === 0}
        className="rounded-md border border-sky-500/40 bg-sky-500/10 px-1.5 py-1 text-[11px] font-medium text-sky-700 hover:bg-sky-500/20 disabled:opacity-50 dark:text-sky-300"
        title={t('review.markAsTransfer', 'Mark as internal transfer')}
        aria-label={t('review.markAsTransfer', 'Mark as internal transfer')}
      >
        {pending ? '…' : '⇄'}
      </button>
      {open && (
        <div className="absolute right-0 top-full z-50 mt-1 w-64 rounded-md border border-border bg-popover p-1 shadow-lg">
          <p className="px-2 py-1 text-[11px] uppercase tracking-wide text-muted-foreground">
            {amount >= 0
              ? t('review.transferFromLabel', 'From')
              : t('review.transferToLabel', 'To')}
          </p>
          <div className="max-h-64 overflow-y-auto">
            {eligible.length === 0 ? (
              <p className="px-2 py-1 text-xs text-muted-foreground">
                {t('review.transferNoAccounts', 'No other accounts available.')}
              </p>
            ) : (
              eligible.map((a) => (
                <button
                  type="button"
                  key={a.id}
                  onClick={() => onPick(a.id)}
                  disabled={pending}
                  className="block w-full truncate rounded-md px-2 py-1 text-left text-xs text-foreground hover:bg-muted disabled:opacity-50"
                  title={a.name}
                >
                  {a.name}
                </button>
              ))
            )}
          </div>
          {error && (
            <p className="border-t border-border px-2 py-1 text-[11px] text-destructive">
              {error}
            </p>
          )}
          <p className="border-t border-border px-2 py-1 text-[10px] text-muted-foreground">
            {t(
              'review.transferHint',
              'Auto-pairs with a matching row on that account, or creates one if none found.',
            )}
          </p>
        </div>
      )}
    </div>
  )
}
