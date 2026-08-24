'use client'

import { cn } from '../../../lib/utils'

export function Card({
  className,
  flush = false,
  ...rest
}: React.HTMLAttributes<HTMLDivElement> & { flush?: boolean }) {
  return <div className={cn(flush ? 'v2-card-flush' : 'v2-card', className)} {...rest} />
}

/**
 * A titled block. The eyebrow is uppercase and tiny so the numbers below it
 * own the visual weight — the label should be findable, not loud.
 */
export function Section({
  title,
  action,
  children,
  className,
  gutter = true,
}: {
  title?: string
  action?: React.ReactNode
  children: React.ReactNode
  className?: string
  gutter?: boolean
}) {
  return (
    <section className={cn('flex flex-col gap-2.5', className)}>
      {(title || action) && (
        <header className={cn('flex items-center justify-between gap-3', gutter && 'v2-gutter')}>
          {title && <h2 className="v2-eyebrow">{title}</h2>}
          {action}
        </header>
      )}
      {children}
    </section>
  )
}

export function Pill({
  tone = 'neutral',
  className,
  ...rest
}: React.HTMLAttributes<HTMLSpanElement> & {
  tone?: 'neutral' | 'positive' | 'negative' | 'warn' | 'accent'
}) {
  const map = {
    neutral: '',
    positive: 'v2-pill-pos',
    negative: 'v2-pill-neg',
    warn: 'v2-pill-warn',
    accent: 'v2-pill-accent',
  } as const
  return <span className={cn('v2-pill', map[tone], className)} {...rest} />
}

export function IconButton({
  label,
  className,
  children,
  ...rest
}: React.ButtonHTMLAttributes<HTMLButtonElement> & { label: string }) {
  return (
    <button type="button" aria-label={label} className={cn('v2-iconbtn', className)} {...rest}>
      {children}
    </button>
  )
}

/** Horizontal meter. `pct` is 0–100; anything outside is clamped. */
export function Track({
  pct,
  color = 'var(--v2-accent)',
  className,
}: {
  pct: number
  color?: string
  className?: string
}) {
  const w = Math.min(100, Math.max(0, Number.isFinite(pct) ? pct : 0))
  return (
    <div className={cn('v2-track', className)}>
      <i style={{ width: `${w}%`, background: color }} />
    </div>
  )
}

export function Empty({
  icon,
  title,
  hint,
  action,
  className,
}: {
  icon?: React.ReactNode
  title: string
  hint?: string
  action?: React.ReactNode
  className?: string
}) {
  return (
    <div
      className={cn(
        'flex flex-col items-center gap-2 px-8 py-12 text-center',
        className,
      )}
    >
      {icon && (
        <div className="mb-1 grid h-12 w-12 place-items-center rounded-2xl bg-[var(--v2-surface-2)] text-[var(--v2-text-3)]">
          {icon}
        </div>
      )}
      <p className="v2-title">{title}</p>
      {hint && <p className="v2-sub max-w-[34ch] text-balance">{hint}</p>}
      {action && <div className="mt-3">{action}</div>}
    </div>
  )
}

export function Skel({ className }: { className?: string }) {
  return <div aria-hidden className={cn('v2-skel', className)} />
}

/** Merchant / account avatar. Falls back to initials over a stable hue. */
export function Bubble({
  label,
  emoji,
  color,
  className,
}: {
  label: string
  emoji?: string | null
  color?: string
  className?: string
}) {
  return (
    <span
      className={cn('v2-bubble', className)}
      style={color ? { background: `color-mix(in oklab, ${color} 16%, transparent)`, color } : undefined}
      aria-hidden
    >
      {emoji || label}
    </span>
  )
}

export function Divider({ className }: { className?: string }) {
  return <div className={cn('v2-divider', className)} />
}
