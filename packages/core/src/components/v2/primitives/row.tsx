'use client'

import { ChevronRight } from 'lucide-react'
import { cn } from '../../../lib/utils'

export interface RowProps {
  leading?: React.ReactNode
  title: React.ReactNode
  subtitle?: React.ReactNode
  /** Right-hand primary value — usually an <Amount />. */
  value?: React.ReactNode
  /** Small line under the value. */
  meta?: React.ReactNode
  chevron?: boolean
  onClick?: () => void
  className?: string
}

/**
 * The list atom used by every screen. Deliberately dumb: it lays out
 * leading / title+subtitle / value+meta and nothing else, so a transaction, an
 * account, a category and a settings entry all sit on the same rhythm.
 */
export function Row({
  leading,
  title,
  subtitle,
  value,
  meta,
  chevron = false,
  onClick,
  className,
}: RowProps) {
  const interactive = Boolean(onClick)
  const Tag = (interactive ? 'button' : 'div') as 'button'
  return (
    <Tag
      type={interactive ? 'button' : undefined}
      onClick={onClick}
      className={cn('v2-row', interactive && 'v2-row-tap', className)}
    >
      {leading}
      <span className="flex min-w-0 flex-1 flex-col gap-0.5">
        <span className="v2-title truncate">{title}</span>
        {subtitle && <span className="v2-sub truncate">{subtitle}</span>}
      </span>
      {(value || meta) && (
        <span className="flex flex-none flex-col items-end gap-0.5 text-right">
          {value && <span className="text-[15px] font-medium">{value}</span>}
          {meta && <span className="v2-micro">{meta}</span>}
        </span>
      )}
      {chevron && (
        <ChevronRight aria-hidden className="h-4 w-4 flex-none text-[var(--v2-text-3)]" />
      )}
    </Tag>
  )
}

/** A card that hosts rows edge-to-edge, with the 1px hairlines between them. */
export function RowGroup({
  children,
  className,
}: {
  children: React.ReactNode
  className?: string
}) {
  return <div className={cn('v2-card-flush', className)}>{children}</div>
}
