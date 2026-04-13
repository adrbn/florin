/**
 * Presentational list of bank connections.
 *
 * Each row shows: bank name, status, valid-until, last sync timestamp / error,
 * and a client-side button row (sync now / reset / disconnect). Parent owns the
 * data fetch — this component just maps rows to cards.
 *
 * Mobile layout stacks info above actions; from `sm:` up, they sit on the
 * same row with actions right-aligned.
 */
import { Landmark } from 'lucide-react'
import { Card } from '../ui/card'
import type { ActionResult } from '../../types/index'
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
}

function formatRelative(date: Date | null): string {
  if (!date) return 'never'
  const diff = Date.now() - date.getTime()
  const minutes = Math.round(diff / 60000)
  if (minutes < 1) return 'just now'
  if (minutes < 60) return `${minutes} min ago`
  const hours = Math.round(minutes / 60)
  if (hours < 24) return `${hours} h ago`
  const days = Math.round(hours / 24)
  return `${days} d ago`
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
}: BankConnectionListProps) {
  if (rows.length === 0) return null

  return (
    <section className="space-y-1.5">
      <h2 className="flex items-center gap-2 px-1 text-[11px] font-semibold uppercase tracking-wider text-muted-foreground">
        <Landmark className="h-3.5 w-3.5" aria-hidden />
        Linked banks ({rows.length})
      </h2>
      <Card className="divide-y divide-border/60 gap-0 overflow-hidden py-0">
        <ul>
          {rows.map((row) => {
            const daysLeft = Math.round(
              (row.validUntil.getTime() - Date.now()) / (24 * 60 * 60 * 1000),
            )
            const tone = statusTone(row.status, row.validUntil)
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
                      {row.status === 'active' ? `${daysLeft}d left` : row.status.toUpperCase()}
                    </span>
                  </div>
                  <p className="text-[11px] text-muted-foreground">
                    Last synced {formatRelative(row.lastSyncedAt)}
                    {row.lastSyncError && (
                      <span className="ml-1 text-destructive" title={row.lastSyncError}>
                        — {row.lastSyncError.length > 80
                          ? `${row.lastSyncError.slice(0, 80)}…`
                          : row.lastSyncError}
                      </span>
                    )}
                  </p>
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
