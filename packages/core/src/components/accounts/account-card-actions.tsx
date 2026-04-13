'use client'

import { useState, useTransition } from 'react'
import { Button } from '../ui/button'
import { ConfirmDialog } from '../ui/confirm-dialog'
import type { ActionResult } from '../../types/index'

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
  onDeleteAccount: (id: string, opts?: { deleteTransactions?: boolean }) => Promise<ActionResult>
  onMergeAccount: (input: { sourceId: string; targetId: string }) => Promise<ActionResult>
  onSetAccountArchived: (id: string, archived: boolean) => Promise<ActionResult>
}

type ConfirmKind = 'archive' | 'delete' | 'merge'

interface ConfirmState {
  kind: ConfirmKind
  title: string
  description: string
  confirmLabel: string
  destructive: boolean
  payload?: { targetId: string; targetName: string }
}

/**
 * Inline per-account actions: archive/unarchive, merge-into, and delete.
 *
 * Archive is the default safe action: it hides the account from the grid and
 * excludes it from net worth, but keeps all transactions. Delete is
 * destructive and cascades. Merge re-parents every transaction onto another
 * account and moves the bank-sync identity over, then drops the empty shell.
 *
 * All three destructive paths go through a proper ConfirmDialog — browser
 * `window.confirm` is too trivial to dismiss accidentally for actions that
 * can wipe hundreds of transactions.
 */
export function AccountCardActions({
  accountId,
  accountName,
  isArchived,
  hasBankSync = false,
  mergeTargets,
  onDeleteAccount,
  onMergeAccount,
  onSetAccountArchived,
}: AccountCardActionsProps) {
  const [pending, startTransition] = useTransition()
  const [error, setError] = useState<string | null>(null)
  const [mergeTargetId, setMergeTargetId] = useState<string>('')
  const [confirm, setConfirm] = useState<ConfirmState | null>(null)
  const [deleteTransactions, setDeleteTransactions] = useState(false)

  const onArchive = () => {
    // Unarchiving and plain archive are benign enough to run without a
    // modal. Only archive-while-bank-synced warrants the dialog because
    // the sync keeps running in the background and that's surprising.
    if (hasBankSync && !isArchived) {
      setConfirm({
        kind: 'archive',
        title: `Archive ${accountName}?`,
        description: `${accountName} still has an active bank sync. Archiving will hide it from the grid and exclude it from net worth, but the sync will keep pulling new transactions in the background.\n\nDisconnect the bank first if you want sync to stop.`,
        confirmLabel: 'Archive anyway',
        destructive: false,
      })
      return
    }
    setError(null)
    startTransition(async () => {
      const result = await onSetAccountArchived(accountId, !isArchived)
      if (!result.success) {
        setError(result.error ?? 'Failed')
      }
    })
  }

  const askDelete = () => {
    setDeleteTransactions(false)
    setConfirm({
      kind: 'delete',
      title: `Delete ${accountName}?`,
      description: '',
      confirmLabel: 'Delete account',
      destructive: true,
    })
  }

  const askMerge = () => {
    const target = mergeTargets.find((t) => t.id === mergeTargetId)
    if (!target) return
    const syncLine = hasBankSync
      ? `\n\nThe bank sync currently on "${accountName}" will move onto "${target.name}", so future bank pushes will land there.`
      : ''
    setConfirm({
      kind: 'merge',
      title: `Merge ${accountName} into ${target.name}?`,
      description: `All transactions on "${accountName}" will be re-parented to "${target.name}", then "${accountName}" will be deleted.${syncLine}\n\nThis cannot be undone.`,
      confirmLabel: `Merge into ${target.name}`,
      destructive: true,
      payload: { targetId: target.id, targetName: target.name },
    })
  }

  const handleConfirm = () => {
    if (!confirm) return
    const current = confirm
    setError(null)
    startTransition(async () => {
      if (current.kind === 'archive') {
        const result = await onSetAccountArchived(accountId, !isArchived)
        if (!result.success) setError(result.error ?? 'Failed')
      } else if (current.kind === 'delete') {
        const result = await onDeleteAccount(accountId, { deleteTransactions })
        if (!result.success) setError(result.error ?? 'Failed')
      } else if (current.kind === 'merge' && current.payload) {
        const result = await onMergeAccount({
          sourceId: accountId,
          targetId: current.payload.targetId,
        })
        if (!result.success) {
          setError(result.error ?? 'Failed')
        } else {
          // Source no longer exists; bounce the user to the list so they
          // don't linger on a dead detail page.
          window.location.href = '/accounts'
          return
        }
      }
      setConfirm(null)
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
            onClick={askMerge}
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
        onClick={askDelete}
        disabled={pending}
        title="Delete forever"
      >
        Delete
      </Button>
      <ConfirmDialog
        open={confirm !== null}
        onOpenChange={(open) => {
          if (!open) setConfirm(null)
        }}
        title={confirm?.title ?? ''}
        description={
          confirm?.kind === 'delete' ? (
            <div className="space-y-3">
              <p>
                The account will be removed. By default, transactions are kept
                and will still appear in the transactions list.
              </p>
              <label className="flex items-center gap-2 rounded-md border border-border bg-muted/30 px-3 py-2 text-sm cursor-pointer">
                <input
                  type="checkbox"
                  checked={deleteTransactions}
                  onChange={(e) => setDeleteTransactions(e.target.checked)}
                  className="rounded"
                />
                <span>Also delete all transactions</span>
              </label>
            </div>
          ) : (
            confirm?.description ?? ''
          )
        }
        confirmLabel={confirm?.confirmLabel ?? 'Confirm'}
        destructive={confirm?.destructive ?? false}
        pending={pending}
        onConfirm={handleConfirm}
      />
    </div>
  )
}
