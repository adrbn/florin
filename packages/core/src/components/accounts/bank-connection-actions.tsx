'use client'

import { Check, RefreshCw, X } from 'lucide-react'
import { useEffect, useRef, useState, useTransition } from 'react'
import { Button } from '../ui/button'
import { ConfirmDialog } from '../ui/confirm-dialog'
import { useT } from '../../i18n/context'
import { cn } from '../../lib/utils'
import type { ActionResult } from '../../types/index'

interface BankConnectionActionsProps {
  connectionId: string
  aspspName: string
  onSyncBankConnection: (connectionId: string) => Promise<ActionResult<{ accountsSynced: number; transactionsInserted: number }>>
  onResetBankConnectionSync: (connectionId: string) => Promise<ActionResult>
  onRevokeBankConnection: (connectionId: string, opts?: { deleteTransactions?: boolean }) => Promise<ActionResult>
}

type ConfirmKind = 'reset' | 'disconnect'

interface ConfirmState {
  kind: ConfirmKind
  title: string
  confirmLabel: string
  destructive: boolean
}

type SyncStatus = 'idle' | 'success' | 'error'
const STATUS_HOLD_MS = 5000

export function BankConnectionActions({
  connectionId,
  aspspName,
  onSyncBankConnection,
  onResetBankConnectionSync,
  onRevokeBankConnection,
}: BankConnectionActionsProps) {
  const t = useT()
  const [pending, startTransition] = useTransition()
  const [message, setMessage] = useState<string | null>(null)
  const [isError, setIsError] = useState(false)
  const [confirm, setConfirm] = useState<ConfirmState | null>(null)
  const [deleteTransactions, setDeleteTransactions] = useState(false)
  const [syncStatus, setSyncStatus] = useState<SyncStatus>('idle')
  const statusTimer = useRef<ReturnType<typeof setTimeout> | null>(null)

  useEffect(() => {
    return () => {
      if (statusTimer.current) clearTimeout(statusTimer.current)
    }
  }, [])

  const onSync = () => {
    setMessage(null)
    setIsError(false)
    if (statusTimer.current) {
      clearTimeout(statusTimer.current)
      statusTimer.current = null
    }
    setSyncStatus('idle')
    startTransition(async () => {
      const result = await onSyncBankConnection(connectionId)
      if (!result.success) {
        setIsError(true)
        const err = result.error ?? 'Sync failed'
        setMessage(err.length > 80 ? `${err.slice(0, 80)}…` : err)
        setSyncStatus('error')
      } else {
        setSyncStatus('success')
      }
      statusTimer.current = setTimeout(() => {
        setSyncStatus('idle')
        statusTimer.current = null
      }, STATUS_HOLD_MS)
    })
  }

  const askReset = () => {
    setConfirm({
      kind: 'reset',
      title: `Reset ${aspspName} sync window?`,
      confirmLabel: 'Reset sync window',
      destructive: true,
    })
  }

  const askDisconnect = () => {
    setDeleteTransactions(false)
    setConfirm({
      kind: 'disconnect',
      title: `Disconnect ${aspspName}?`,
      confirmLabel: 'Disconnect',
      destructive: true,
    })
  }

  const handleConfirm = () => {
    if (!confirm) return
    const kind = confirm.kind
    setMessage(null)
    setIsError(false)
    startTransition(async () => {
      if (kind === 'reset') {
        const result = await onResetBankConnectionSync(connectionId)
        if (!result.success) {
          setIsError(true)
          setMessage(result.error ?? 'Reset failed')
        } else {
          setMessage(
            'Sync window reset — next sync will only fetch transactions from today onward.',
          )
        }
      } else {
        const result = await onRevokeBankConnection(connectionId, { deleteTransactions })
        if (!result.success) {
          setIsError(true)
          setMessage(result.error ?? 'Disconnect failed')
        }
      }
      setConfirm(null)
    })
  }

  const dialogDescription = confirm?.kind === 'reset'
    ? 'This deletes every bank-API transaction for this connection and sets the sync start date to today.\n\nLegacy and manual transactions stay untouched. Use this only to recover from overlap with XLSX imports.'
    : (
        <div className="space-y-3">
          <p>Linked accounts are kept but converted to manual mode and will no longer auto-sync.</p>
          <p>You can re-link the bank later if you change your mind, but the consent flow has to run again.</p>
          <label className="flex items-center gap-2 rounded-md border border-border bg-muted/30 px-3 py-2 text-sm cursor-pointer">
            <input
              type="checkbox"
              checked={deleteTransactions}
              onChange={(e) => setDeleteTransactions(e.target.checked)}
              className="rounded"
            />
            <span>Also delete all bank-synced transactions</span>
          </label>
        </div>
      )

  const showCheck = syncStatus === 'success' && !pending
  const showCross = syncStatus === 'error' && !pending

  return (
    <div className="flex flex-col items-stretch gap-2 sm:flex-row sm:items-center sm:gap-2">
      {isError && message && (
        <span
          className="block max-w-full truncate text-[11px] leading-tight text-destructive sm:max-w-[24ch] sm:text-right"
          role="status"
          title={message}
        >
          {message}
        </span>
      )}
      <div className="flex flex-wrap items-center justify-end gap-1.5">
        <Button
          size="sm"
          variant="outline"
          onClick={onSync}
          disabled={pending}
          className={cn(
            'gap-1.5 transition-colors',
            showCheck &&
              'border-emerald-500/40 bg-emerald-500/10 text-emerald-700 hover:bg-emerald-500/15 hover:text-emerald-700 dark:text-emerald-300',
            showCross &&
              'border-destructive/40 bg-destructive/10 text-destructive hover:bg-destructive/15 hover:text-destructive',
          )}
          aria-label={t('accounts.syncNow', 'Sync now')}
        >
          {showCheck ? (
            <Check className="h-3.5 w-3.5" />
          ) : showCross ? (
            <X className="h-3.5 w-3.5" />
          ) : (
            <RefreshCw className={cn('h-3.5 w-3.5', pending && 'animate-spin')} />
          )}
          {pending && !confirm
            ? t('accounts.syncing', 'Syncing…')
            : showCheck
              ? t('dashboard.synced', 'Synced')
              : showCross
                ? t('accounts.syncFailed', 'Failed')
                : t('accounts.syncNow', 'Sync now')}
        </Button>
        <Button size="sm" variant="ghost" onClick={askReset} disabled={pending}>
          {t('accounts.reset', 'Reset')}
        </Button>
        <Button size="sm" variant="ghost" onClick={askDisconnect} disabled={pending}>
          {t('accounts.disconnect', 'Disconnect')}
        </Button>
      </div>
      <ConfirmDialog
        open={confirm !== null}
        onOpenChange={(open) => {
          if (!open) setConfirm(null)
        }}
        title={confirm?.title ?? ''}
        description={dialogDescription}
        confirmLabel={confirm?.confirmLabel ?? 'Confirm'}
        destructive={confirm?.destructive ?? false}
        pending={pending}
        onConfirm={handleConfirm}
      />
    </div>
  )
}
