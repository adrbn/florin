'use client'

import { useTransition } from 'react'
import { useT } from '../../i18n/context'
import type { ActionResult } from '../../types/index'

interface ApproveAllButtonProps {
  count: number
  onApproveAllTransactions: () => Promise<ActionResult<{ approved: number }>>
}

/**
 * "Approve all" escape hatch for the review queue. Confirms before firing
 * because it touches every pending row in one shot.
 */
export function ApproveAllButton({ count, onApproveAllTransactions }: ApproveAllButtonProps) {
  const t = useT()
  const [pending, startTransition] = useTransition()

  const onClick = () => {
    if (count === 0) return
    if (
      !window.confirm(
        t(
          'review.approveAllConfirm',
          { count },
          `Approve all ${count} pending transactions? You can still recategorize them later.`,
        ),
      )
    ) {
      return
    }
    startTransition(async () => {
      await onApproveAllTransactions()
    })
  }

  return (
    <button
      type="button"
      onClick={onClick}
      disabled={pending || count === 0}
      className="rounded-md border border-emerald-500/40 bg-emerald-500/10 px-3 py-1.5 text-xs font-medium text-emerald-700 hover:bg-emerald-500/20 disabled:opacity-50 dark:text-emerald-300"
    >
      {pending
        ? t('review.approving', 'Approving…')
        : t('review.approveAllCount', { count }, `Approve all (${count})`)}
    </button>
  )
}
