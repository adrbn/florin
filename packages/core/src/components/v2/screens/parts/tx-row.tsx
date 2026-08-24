'use client'

import { ArrowLeftRight } from 'lucide-react'
import { Amount } from '../../primitives/amount'
import { Row } from '../../primitives/row'
import { useV2T } from '../../i18n/context'
import { humanizePayee, initials, seriesVar } from '../../lib/format'
import type { V2Tx } from '../../types'

/**
 * One transaction line.
 *
 * The bubble prefers the category emoji, because a wall of coloured initials is
 * noise — an emoji column lets the eye group "food" and "transport" without
 * reading a single word. Initials over a stable hue are the fallback for the
 * uncategorized, which doubles as a visual cue that something needs a category.
 */
export function TxRow({
  tx,
  secondary,
  onClick,
  className,
}: {
  tx: V2Tx
  /** Overrides the default subtitle (category · account) — used for date grouping. */
  secondary?: string
  onClick?: () => void
  className?: string
}) {
  const t = useV2T()
  const label = humanizePayee(tx.payee)
  const color = seriesVar(tx.categoryName ?? tx.payee)

  const bits = [
    tx.categoryName ?? t('v2.common.uncategorized', 'Uncategorized'),
    secondary ?? tx.accountName,
  ].filter(Boolean)

  return (
    <Row
      leading={
        <span
          className="v2-bubble"
          style={{ background: `color-mix(in oklab, ${color} 14%, transparent)`, color }}
          aria-hidden
        >
          {tx.isTransfer ? (
            <ArrowLeftRight className="h-[17px] w-[17px]" strokeWidth={1.9} />
          ) : tx.categoryEmoji ? (
            <span className="text-[17px]">{tx.categoryEmoji}</span>
          ) : (
            initials(label)
          )}
        </span>
      }
      title={label}
      subtitle={bits.join(' · ')}
      value={<Amount value={tx.amount} signed tone="auto" />}
      meta={
        tx.needsReview ? (
          <span className="text-[var(--v2-neg)]">{t('v2.activity.needsReview', 'To review')}</span>
        ) : tx.isScheduled ? (
          <span>{t('v2.activity.scheduled', 'Scheduled')}</span>
        ) : tx.isPending ? (
          <span>{t('v2.activity.pending', 'Pending')}</span>
        ) : undefined
      }
      onClick={onClick}
      className={className}
    />
  )
}
