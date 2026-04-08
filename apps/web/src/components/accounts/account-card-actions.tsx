'use client'

import { useState, useTransition } from 'react'
import { Button } from '@/components/ui/button'
import { deleteAccount, setAccountArchived } from '@/server/actions/accounts'

interface AccountCardActionsProps {
  accountId: string
  accountName: string
  isArchived: boolean
  /** true if this account still has bank sync active — archiving it is usually wrong. */
  hasBankSync?: boolean
}

/**
 * Inline per-account actions: archive/unarchive and delete.
 *
 * Archive is the default safe action: it hides the account from the grid and
 * excludes it from net worth, but keeps all transactions. Delete is
 * destructive and cascades — we gate it behind a confirm prompt.
 */
export function AccountCardActions({
  accountId,
  accountName,
  isArchived,
  hasBankSync = false,
}: AccountCardActionsProps) {
  const [pending, startTransition] = useTransition()
  const [error, setError] = useState<string | null>(null)

  const onArchive = () => {
    if (hasBankSync && !isArchived) {
      const ok = window.confirm(
        `${accountName} still has an active bank sync. Archiving will hide it from the grid and net worth, but the sync will keep running. Continue?`,
      )
      if (!ok) return
    }
    setError(null)
    startTransition(async () => {
      const result = await setAccountArchived(accountId, !isArchived)
      if (!result.success) {
        setError(result.error ?? 'Failed')
      }
    })
  }

  const onDelete = () => {
    const ok = window.confirm(
      `Permanently delete "${accountName}"?\n\nAll transactions for this account will also be deleted. This cannot be undone. Prefer Archive unless you really want the data gone.`,
    )
    if (!ok) return
    setError(null)
    startTransition(async () => {
      const result = await deleteAccount(accountId)
      if (!result.success) {
        setError(result.error ?? 'Failed')
      }
    })
  }

  return (
    <div className="flex items-center gap-1">
      {error && (
        <span className="text-[10px] text-destructive" role="status">
          {error}
        </span>
      )}
      <Button
        size="sm"
        variant="ghost"
        onClick={onArchive}
        disabled={pending}
        title={
          isArchived ? 'Unarchive — show in grid again' : 'Archive — hide from grid + net worth'
        }
      >
        {isArchived ? 'Unarchive' : 'Archive'}
      </Button>
      <Button
        size="sm"
        variant="ghost"
        onClick={onDelete}
        disabled={pending}
        title="Delete forever"
      >
        Delete
      </Button>
    </div>
  )
}
