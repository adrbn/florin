'use client'

import { useState } from 'react'
import { cn } from '../../../lib/utils'

export interface BarDatum {
  key: string
  label: string
  income: number
  expense: number
  net: number
}

/**
 * Income-vs-spending column pair.
 *
 * Both series share one scale (the largest absolute value across both), which
 * is the only way the bars stay comparable — normalising each series to its own
 * max is the classic way to make a €400 month look like a €4 000 one.
 */
export function FlowBars({
  data,
  height = 148,
  onSelect,
  selected,
  describe,
  className,
}: {
  data: BarDatum[]
  height?: number
  onSelect?: (d: BarDatum | null) => void
  selected?: string | null
  /** Accessible name for a column — without it these are 12 nameless buttons. */
  describe?: (d: BarDatum) => string
  className?: string
}) {
  const [hover, setHover] = useState<string | null>(null)
  const max = Math.max(1, ...data.flatMap((d) => [Math.abs(d.income), Math.abs(d.expense)]))
  const active = selected ?? hover

  return (
    <div className={cn('flex items-end gap-[3px]', className)} style={{ height }}>
      {data.map((d) => {
        const ih = Math.max(2, (Math.abs(d.income) / max) * (height - 18))
        const eh = Math.max(2, (Math.abs(d.expense) / max) * (height - 18))
        const isActive = active === d.key
        return (
          <button
            key={d.key}
            type="button"
            onPointerEnter={() => setHover(d.key)}
            onPointerLeave={() => setHover(null)}
            onClick={() => onSelect?.(isActive ? null : d)}
            aria-label={describe?.(d) ?? d.label}
            aria-pressed={isActive}
            className="group flex min-w-0 flex-1 flex-col items-center justify-end gap-1"
            style={{ height }}
          >
            <span className="flex w-full items-end justify-center gap-[2px]" style={{ flex: 1 }}>
              <i
                className="block w-full max-w-[9px] rounded-t-[3px] transition-opacity"
                style={{
                  height: ih,
                  background: 'var(--v2-pos)',
                  opacity: active && !isActive ? 0.32 : 0.9,
                }}
              />
              <i
                className="block w-full max-w-[9px] rounded-t-[3px] transition-opacity"
                style={{
                  height: eh,
                  background: 'var(--v2-neg)',
                  opacity: active && !isActive ? 0.32 : 0.9,
                }}
              />
            </span>
            <span
              className={cn(
                'v2-num text-[9.5px] leading-none transition-colors',
                isActive ? 'text-[var(--v2-text)]' : 'text-[var(--v2-text-3)]',
              )}
            >
              {d.label}
            </span>
          </button>
        )
      })}
    </div>
  )
}

export interface RankBarItem {
  key: string
  label: string
  emoji?: string | null
  value: number
  color?: string
}

/**
 * Ranked horizontal bars — "where the money went". Reads far better than a pie
 * on a 390px screen: the labels sit on the baseline instead of on leader lines,
 * and the eye compares lengths against a shared left edge.
 */
export function RankBars({
  items,
  format,
  onSelect,
  className,
}: {
  items: RankBarItem[]
  format: (v: number) => string
  onSelect?: (item: RankBarItem) => void
  className?: string
}) {
  const max = Math.max(1, ...items.map((i) => Math.abs(i.value)))
  return (
    <div className={cn('flex flex-col', className)}>
      {items.map((item) => {
        const pct = (Math.abs(item.value) / max) * 100
        const interactive = Boolean(onSelect)
        const Tag = (interactive ? 'button' : 'div') as 'button'
        return (
          <Tag
            key={item.key}
            type={interactive ? 'button' : undefined}
            onClick={interactive ? () => onSelect?.(item) : undefined}
            className={cn(
              'flex w-full flex-col gap-1.5 px-[var(--v2-gutter)] py-2.5 text-left',
              interactive && 'v2-row-tap active:scale-[0.99]',
            )}
          >
            <span className="flex items-baseline gap-2">
              {item.emoji && <span className="text-[13px] leading-none">{item.emoji}</span>}
              <span className="v2-title min-w-0 flex-1 truncate">{item.label}</span>
              <span data-amount="v2" className="v2-num text-[13.5px] font-medium">
                {format(item.value)}
              </span>
            </span>
            <span className="v2-track h-[5px]">
              <i
                style={{
                  width: `${pct}%`,
                  background: item.color ?? 'var(--v2-accent)',
                }}
              />
            </span>
          </Tag>
        )
      })}
    </div>
  )
}
