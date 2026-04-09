'use client'

import { useState, useTransition } from 'react'
import { Button } from '@/components/ui/button'
import { deleteAccount, mergeAccount, setAccountArchived } from '@/server/actions/accounts'

interface MergeTarget {
  id: string
  name: string
}

interface AccountCardActionsProps {
  accountId: string
  accountName: string
  isArchived: boolean
  /** true if this account still has bank sync active — archiving it is usually wrong. */
  hasBankSync?: boolean
  /** Every other non-archived account, used to populate the "merge into" picker. */
  mergeTargets: ReadonlyArray<MergeTarget>
}

/**
 * Inline per-account actions: archive/unarchive, merge-into, and delete.
 *
 * Archive is the default safe action: it hides the account from the grid and
 * excludes it from net worth, but keeps all transactions. Delete is
 * destructive and cascades — we gate it behind a confirm prompt.
 *
 * Merge re-parents every transaction onto another account and moves the
 * bank-sync identity over, then drops the empty shell. It's the right
 * answer when a bank-synced account overlaps a legacy manual account
 * (e.g. "La Banque Postale ·3546" duplicating CCP).
 */
export function AccountCardActions({
  accountId,
  accountName,
  isArchived,
  hasBankSync = false,
  mergeTargets,
}: AccountCardActionsProps) {
  const [pending, startTransition] = useTransition()
  const [error, setError] = useState<string | null>(null)
  const [mergeTargetId, setMergeTargetId] = useState<string>('')

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

  const onMerge = () => {
    const target = mergeTargets.find((t) => t.id === mergeTargetId)
    if (!target) return
    const hasSyncWarning = hasBankSync
      ? `\n\nThe bank sync currently on "${accountName}" will move onto "${target.name}", so future bank pushes will land there.`
      : ''
    const ok = window.confirm(
      `Merge "${accountName}" into "${target.name}"?\n\nAll transactions on "${accountName}" will be re-parented to "${target.name}", then "${accountName}" will be deleted.${hasSyncWarning}\n\nThis cannot be undone.`,
    )
    if (!ok) return
    setError(null)
    startTransition(async () => {
      const result = await mergeAccount({ sourceId: accountId, targetId: target.id })
      if (!result.success) {
        setError(result.error ?? 'Failed')
        return
      }
      // On success the source account no longer exists — Next.js revalidation
      // will kick in but the user is still on a dead detail page, so push
      // them back to the list.
      window.location.href = '/accounts'
    })
  }

  return (
    <div className="flex flex-wrap items-center gap-2">
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
      {mergeTargets.length > 0 && (
        <div className="flex items-center gap-1">
          <select
            value={mergeTargetId}
            onChange={(e) => setMergeTargetId(e.target.value)}
            disabled={pending}
            className="h-8 rounded-md border border-border bg-background px-2 text-xs"
            aria-label="Merge into account"
          >
            <option value="">Merge into…</option>
            {mergeTargets.map((t) => (
              <option key={t.id} value={t.id}>
                {t.name}
              </option>
            ))}
          </select>
          <Button
            size="sm"
            variant="ghost"
            onClick={onMerge}
            disabled={pending || !mergeTargetId}
            title="Move all transactions and bank sync onto the target account, then delete this one"
          >
            Merge
          </Button>
        </div>
      )}
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
