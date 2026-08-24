'use client'

import { useMoney } from '../lib/config'
import { cn } from '../../../lib/utils'

/**
 * Every v2 amount carries `data-amount` explicitly.
 *
 * The app-wide privacy walker tags any element whose text node holds BOTH a
 * digit and a currency symbol. The hero splits those across sibling spans —
 * "128 404" here, ",17 €" there — so the auto-tagger would blur the cents and
 * leave the euros in the clear. Marking the wrapper ourselves is what keeps
 * ⌘H honest on this surface.
 */

type Tone = 'auto' | 'neutral' | 'positive' | 'negative' | 'muted'

function toneClass(tone: Tone, value: number): string {
  const t = tone === 'auto' ? (value > 0 ? 'positive' : value < 0 ? 'negative' : 'neutral') : tone
  switch (t) {
    case 'positive':
      return 'text-[var(--v2-pos)]'
    case 'negative':
      return 'text-[var(--v2-neg)]'
    case 'muted':
      return 'text-[var(--v2-text-3)]'
    default:
      return 'text-[var(--v2-text)]'
  }
}

export interface AmountProps {
  value: number
  signed?: boolean
  decimals?: boolean
  tone?: Tone
  className?: string
}

/** Inline amount — rows, chips, table cells. One text node, one tone. */
export function Amount({
  value,
  signed = false,
  decimals = true,
  tone = 'neutral',
  className,
}: AmountProps) {
  const m = useMoney()
  return (
    <span
      data-amount="v2"
      className={cn('v2-num', toneClass(tone, value), className)}
    >
      {m.fmt(value, { signed, decimals })}
    </span>
  )
}

export interface HeroAmountProps extends AmountProps {
  /** Demote the cents to ~44% size and mute them. The whole point of the hero. */
  demoteCents?: boolean
}

/**
 * The headline figure. Renders "128 404" at full size with ",17 €" small and
 * muted beside it — the single typographic move that separates a premium
 * finance app from a spreadsheet.
 */
export function HeroAmount({
  value,
  signed = false,
  decimals = true,
  tone = 'neutral',
  demoteCents = true,
  className,
}: HeroAmountProps) {
  const m = useMoney()
  const p = m.parts(value, { signed, decimals })
  const tail = `${p.decimal}${p.fraction}`

  return (
    <span
      data-amount="v2"
      className={cn('v2-num v2-hero inline-flex items-baseline', toneClass(tone, value), className)}
    >
      {p.sign && <span>{p.sign}</span>}
      {p.currencyFirst && <span>{p.currency}</span>}
      <span>{p.integer}</span>
      {decimals && tail && (
        <span className={demoteCents ? 'v2-hero-cents' : undefined}>{tail}</span>
      )}
      {!p.currencyFirst && (
        <span className={demoteCents ? 'v2-hero-cents' : undefined}>
          {' '}
          {p.currency}
        </span>
      )}
    </span>
  )
}

/**
 * The delta chip under a hero: "▲ 1 240 € · sur un mois". Renders nothing at
 * all when there is no comparison to make, rather than a sad "—".
 */
export function DeltaChip({
  value,
  suffix,
  pct,
  className,
}: {
  value: number | null
  suffix?: string
  /** Optional percentage shown next to the absolute delta. */
  pct?: number | null
  className?: string
}) {
  const m = useMoney()
  if (value === null || !Number.isFinite(value)) return null
  const up = value > 0
  const flat = Math.abs(value) < 0.005
  return (
    <span
      className={cn(
        'inline-flex items-center gap-1.5 text-[13px] font-medium',
        flat
          ? 'text-[var(--v2-text-3)]'
          : up
            ? 'text-[var(--v2-pos)]'
            : 'text-[var(--v2-neg)]',
        className,
      )}
    >
      {!flat && (
        <span aria-hidden className="text-[10px] leading-none">
          {up ? '▲' : '▼'}
        </span>
      )}
      <span data-amount="v2" className="v2-num">
        {m.fmt(Math.abs(value), { decimals: Math.abs(value) < 1000 })}
      </span>
      {pct !== undefined && pct !== null && Number.isFinite(pct) && (
        <span className="v2-num opacity-70">({m.pct(pct)})</span>
      )}
      {suffix && <span className="font-normal text-[var(--v2-text-3)]">{suffix}</span>}
    </span>
  )
}
