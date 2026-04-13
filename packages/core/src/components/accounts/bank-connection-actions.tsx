'use client'

import { useState, useTransition } from 'react'
import { Button } from '../ui/button'
import { ConfirmDialog } from '../ui/confirm-dialog'
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

export function BankConnectionActions({
  connectionId,
  aspspName,
  onSyncBankConnection,
  onResetBankConnectionSync,
  onRevokeBankConnection,
}: BankConnectionActionsProps) {
  const [pending, startTransition] = useTransition()
  const [message, setMessage] = useState<string | null>(null)
  const [isError, setIsError] = useState(false)
  const [confirm, setConfirm] = useState<ConfirmState | null>(null)
  const [deleteTransactions, setDeleteTransactions] = useState(false)

  const onSync = () => {
    setMessage(null)
    setIsError(false)
    startTransition(async () => {
      const result = await onSyncBankConnection(connectionId)
      if (!result.success) {
        setIsError(true)
        setMessage(result.error ?? 'Sync failed')
        return
      }
      const { accountsSynced, transactionsInserted } = result.data ?? {
        accountsSynced: 0,
        transactionsInserted: 0,
      }
      setIsError(false)
      setMessage(`Synced ${accountsSynced} accounts, +${transactionsInserted} transactions`)
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

  return (
    <div className="flex flex-col items-stretch gap-2 sm:flex-row sm:items-center sm:gap-2">
      {message && (
        <span
          className={`text-[11px] leading-tight sm:max-w-[18ch] sm:text-right ${
            isError ? 'text-destructive' : 'text-muted-foreground'
          }`}
          role="status"
        >
          {message}
        </span>
      )}
      <div className="flex flex-wrap items-center justify-end gap-1.5">
        <Button size="sm" variant="outline" onClick={onSync} disabled={pending}>
          {pending && !confirm ? 'Syncing…' : 'Sync now'}
        </Button>
        <Button size="sm" variant="ghost" onClick={askReset} disabled={pending}>
          Reset
        </Button>
        <Button size="sm" variant="ghost" onClick={askDisconnect} disabled={pending}>
          Disconnect
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
