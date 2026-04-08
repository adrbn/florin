'use client'

import { useState, useTransition } from 'react'
import { Button } from '@/components/ui/button'
import {
  resetBankConnectionSync,
  revokeBankConnection,
  syncBankConnection,
} from '@/server/actions/banking'

interface BankConnectionActionsProps {
  connectionId: string
  aspspName: string
}

/**
 * Client-side action buttons for one bank_connections row.
 *
 * Sync runs the server action and surfaces the inserted-transaction count
 * inline. Disconnect prompts for confirmation because it cascades to nulling
 * the FK on linked accounts (which we explain in the prompt copy).
 */
export function BankConnectionActions({ connectionId, aspspName }: BankConnectionActionsProps) {
  const [pending, startTransition] = useTransition()
  const [message, setMessage] = useState<string | null>(null)
  const [isError, setIsError] = useState(false)

  const onSync = () => {
    setMessage(null)
    setIsError(false)
    startTransition(async () => {
      const result = await syncBankConnection(connectionId)
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

  const onReset = () => {
    const ok = window.confirm(
      `Reset ${aspspName} sync window?\n\nThis deletes every bank-API transaction for this connection and sets the sync start date to today. Your legacy/manual transactions stay untouched. Use this to recover from overlap with XLSX imports.`,
    )
    if (!ok) return
    setMessage(null)
    setIsError(false)
    startTransition(async () => {
      const result = await resetBankConnectionSync(connectionId)
      if (!result.success) {
        setIsError(true)
        setMessage(result.error ?? 'Reset failed')
        return
      }
      setIsError(false)
      setMessage('Sync window reset — next sync will only fetch transactions from today onward.')
    })
  }

  const onDisconnect = () => {
    const ok = window.confirm(
      `Disconnect ${aspspName}? Linked accounts will be kept but converted to manual mode and will no longer auto-sync. Existing transactions stay.`,
    )
    if (!ok) return
    setMessage(null)
    setIsError(false)
    startTransition(async () => {
      const result = await revokeBankConnection(connectionId)
      if (!result.success) {
        setIsError(true)
        setMessage(result.error ?? 'Disconnect failed')
      }
    })
  }

  return (
    <div className="flex items-center gap-2">
      {message && (
        <span
          className={`text-xs ${isError ? 'text-destructive' : 'text-muted-foreground'}`}
          role="status"
        >
          {message}
        </span>
      )}
      <Button size="sm" variant="outline" onClick={onSync} disabled={pending}>
        {pending ? 'Syncing…' : 'Sync now'}
      </Button>
      <Button size="sm" variant="ghost" onClick={onReset} disabled={pending}>
        Reset
      </Button>
      <Button size="sm" variant="ghost" onClick={onDisconnect} disabled={pending}>
        Disconnect
      </Button>
    </div>
  )
}
