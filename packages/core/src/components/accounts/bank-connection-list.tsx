/**
 * Presentational list of bank connections.
 *
 * Each row shows: bank name, status, valid-until, last sync timestamp / error,
 * and a client-side button row (sync now / reset / disconnect). Parent owns the
 * data fetch — this component just maps rows to cards.
 *
 * Mobile layout stacks info above actions; from `sm:` up, they sit on the
 * same row with actions right-aligned.
 *
 * Client component because it calls `useT()` to localize the relative time
 * label — the parent accounts page is a server component.
 */
'use client'

import { Landmark } from 'lucide-react'
import { Card } from '../ui/card'
import type { ActionResult } from '../../types/index'
import { useT } from '../../i18n/context'
import type { TFunction } from '../../i18n'
import { BankConnectionActions } from './bank-connection-actions'

export interface BankConnectionRow {
  id: string
  aspspName: string
  status: string
  validUntil: Date
  lastSyncedAt: Date | null
  lastSyncError: string | null
  createdAt: Date
}

interface BankConnectionListProps {
  rows: ReadonlyArray<BankConnectionRow>
  onSyncBankConnection: (connectionId: string) => Promise<ActionResult<{ accountsSynced: number; transactionsInserted: number }>>
  onResetBankConnectionSync: (connectionId: string) => Promise<ActionResult>
  onRevokeBankConnection: (connectionId: string) => Promise<ActionResult>
  labels?: {
    linkedBanks?: string
    lastSyncedPrefix?: string
  }
}

function formatRelative(date: Date | null, t: TFunction): string {
  if (!date) return t('bankSync.never', 'never')
  const diff = Date.now() - date.getTime()
  const minutes = Math.round(diff / 60000)
  if (minutes < 1) return t('bankSync.justNow', 'just now')
  if (minutes < 60) return t('bankSync.minAgo', { n: minutes }, '{n} min ago')
  const hours = Math.round(minutes / 60)
  if (hours < 24) return t('bankSync.hAgo', { n: hours }, '{n} h ago')
  const days = Math.round(hours / 24)
  return t('bankSync.dAgo', { n: days }, '{n} d ago')
}

/**
 * `lastSyncError` doubles as a status channel: a hard failure is a plain
 * message (shown red), while a soft, non-error observation is written as
 * `[info:<token>]` by the sync (shown amber). This maps the known tokens to a
 * localized, actionable hint so a "synced fine but got nothing" run doesn't
 * look identically healthy to a real sync. Returns null when it's not an info
 * note.
 */
function bankInfoHint(raw: string | null, t: TFunction): string | null {
  if (!raw || !raw.startsWith('[info')) return null
  const token = raw.match(/^\[info:([a-z_]+)\]/)?.[1]
  if (token === 'no_accounts') {
    return t(
      'bankSync.hintNoAccounts',
      "0 account exposed — this bank may not share accounts over open banking (PSD2).",
    )
  }
  if (token === 'no_transactions') {
    return t(
      'bankSync.hintNoTransactions',
      'Accounts found but 0 transactions — this bank may not expose transaction details.',
    )
  }
  // Unknown/freeform info note: strip the prefix and show the remainder.
  return raw.replace(/^\[info:?[a-z_]*\]\s*/, '') || null
}

function statusTone(status: string, validUntil: Date): string {
  if (status !== 'active') return 'border-destructive/40 bg-destructive/10 text-destructive'
  const daysLeft = Math.round((validUntil.getTime() - Date.now()) / (24 * 60 * 60 * 1000))
  if (daysLeft <= 7) return 'border-amber-500/40 bg-amber-500/10 text-amber-800 dark:text-amber-200'
  return 'border-emerald-500/40 bg-emerald-500/10 text-emerald-800 dark:text-emerald-200'
}

export function BankConnectionList({
  rows,
  onSyncBankConnection,
  onResetBankConnectionSync,
  onRevokeBankConnection,
  labels,
}: BankConnectionListProps) {
  const t = useT()
  if (rows.length === 0) return null

  const linkedBanks = labels?.linkedBanks ?? t('accounts.linkedBanks', 'Linked banks')
  const lastSyncedPrefix = labels?.lastSyncedPrefix ?? t('bankSync.lastSyncedPrefix', 'Last synced')

  return (
    <section className="space-y-1.5">
      <h2 className="flex items-center gap-2 px-1 text-[11px] font-semibold uppercase tracking-wider text-muted-foreground">
        <Landmark className="h-3.5 w-3.5" aria-hidden />
        {linkedBanks} ({rows.length})
      </h2>
      <Card className="divide-y divide-border/60 gap-0 overflow-hidden py-0">
        <ul>
          {rows.map((row) => {
            const daysLeft = Math.round(
              (row.validUntil.getTime() - Date.now()) / (24 * 60 * 60 * 1000),
            )
            const tone = statusTone(row.status, row.validUntil)
            const infoHint = bankInfoHint(row.lastSyncError, t)
            const errorText =
              row.lastSyncError && !row.lastSyncError.startsWith('[info') ? row.lastSyncError : null
            return (
              <li
                key={row.id}
                className="flex flex-col gap-3 px-3 py-3 sm:flex-row sm:items-center sm:justify-between sm:gap-4"
              >
                <div className="min-w-0 space-y-0.5">
                  <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
                    <span className="text-sm font-medium leading-tight break-words">
                      {row.aspspName}
                    </span>
                    <span
                      className={`inline-flex shrink-0 items-center rounded-full border px-2 py-0.5 text-[10px] font-medium uppercase tracking-wide ${tone}`}
                      title={`Consent valid until ${row.validUntil.toLocaleDateString()}`}
                    >
                      {row.status === 'active'
                        ? t('bankSync.daysLeft', { n: daysLeft }, '{n}d left')
                        : row.status.toUpperCase()}
                    </span>
                  </div>
                  <p className="truncate text-[11px] text-muted-foreground" title={errorText ?? undefined}>
                    {lastSyncedPrefix} {formatRelative(row.lastSyncedAt, t)}
                    {errorText && (
                      <span className="ml-1 text-destructive">
                        — {errorText.length > 60 ? `${errorText.slice(0, 60)}…` : errorText}
                      </span>
                    )}
                  </p>
                  {infoHint && (
                    <p className="flex items-start gap-1 text-[11px] text-amber-700 dark:text-amber-300">
                      <span aria-hidden>⚠</span>
                      <span className="min-w-0">{infoHint}</span>
                    </p>
                  )}
                </div>
                <BankConnectionActions
                  connectionId={row.id}
                  aspspName={row.aspspName}
                  onSyncBankConnection={onSyncBankConnection}
                  onResetBankConnectionSync={onResetBankConnectionSync}
                  onRevokeBankConnection={onRevokeBankConnection}
                />
              </li>
            )
          })}
        </ul>
      </Card>
    </section>
  )
}
