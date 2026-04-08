/**
 * Server component that lists all active bank_connections rows.
 *
 * Each row shows: bank name, status, valid-until, last sync timestamp / error,
 * and a client-side button row (sync now / disconnect). We don't paginate
 * because a self-hosted user is unlikely to link more than a handful of banks.
 */
import { desc } from 'drizzle-orm'
import { Card, CardContent } from '@/components/ui/card'
import { db } from '@/db/client'
import { bankConnections } from '@/db/schema'
import { BankConnectionActions } from './bank-connection-actions'

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

export async function BankConnectionList() {
  const rows = await db.select().from(bankConnections).orderBy(desc(bankConnections.createdAt))
  if (rows.length === 0) return null

  return (
    <Card>
      <CardContent className="space-y-2 py-4">
        <h2 className="text-sm font-semibold text-muted-foreground uppercase tracking-wide">
          Linked banks ({rows.length})
        </h2>
        <ul className="divide-y divide-border">
          {rows.map((row) => {
            const daysLeft = Math.round(
              (row.validUntil.getTime() - Date.now()) / (24 * 60 * 60 * 1000),
            )
            const tone = statusTone(row.status, row.validUntil)
            return (
              <li key={row.id} className="flex flex-wrap items-center justify-between gap-3 py-3">
                <div className="min-w-0 flex-1 space-y-1">
                  <div className="flex items-center gap-2">
                    <span className="font-medium">{row.aspspName}</span>
                    <span
                      className={`inline-flex items-center rounded-full border px-2 py-0.5 text-[10px] font-medium uppercase tracking-wide ${tone}`}
                      title={`Consent valid until ${row.validUntil.toLocaleDateString()}`}
                    >
                      {row.status === 'active' ? `${daysLeft}d left` : row.status.toUpperCase()}
                    </span>
                  </div>
                  <p className="text-xs text-muted-foreground">
                    Last synced {formatRelative(row.lastSyncedAt)}
                    {row.lastSyncError && (
                      <span className="ml-2 text-destructive">— {row.lastSyncError}</span>
                    )}
                  </p>
                </div>
                <BankConnectionActions connectionId={row.id} aspspName={row.aspspName} />
              </li>
            )
          })}
        </ul>
      </CardContent>
    </Card>
  )
}
