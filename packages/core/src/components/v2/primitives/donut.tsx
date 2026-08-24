'use client'

import { useId } from 'react'
import { cn } from '../../../lib/utils'

export interface DonutSlice {
  key: string
  label: string
  value: number
  color: string
}

/**
 * Allocation donut.
 *
 * Drawn with stroke-dasharray on a single circle rather than arc paths — an
 * arc path with a rounded cap needs its own geometry per slice and drifts a
 * fraction of a degree per segment; a dashed circle is exact by construction
 * and lets the gap between slices be a constant number of pixels.
 */
export function Donut({
  slices,
  size = 132,
  thickness = 13,
  centerLabel,
  centerValue,
  className,
}: {
  slices: DonutSlice[]
  size?: number
  thickness?: number
  centerLabel?: string
  centerValue?: React.ReactNode
  className?: string
}) {
  const id = useId().replace(/:/g, '')
  const total = slices.reduce((s, x) => s + Math.max(0, x.value), 0)
  const r = (size - thickness) / 2
  const c = 2 * Math.PI * r
  // A round linecap sticks out by half the stroke width past the dash it
  // terminates. Subtracting a full thickness from the dash and pushing the
  // start forward by half gives back exactly the room the two caps need — with
  // a plain 2px gap the caps overlapped and the seam showed a notch.
  const inset = slices.filter((s) => s.value > 0).length > 1 ? thickness : 0

  let offset = 0
  const arcs = slices
    .filter((s) => s.value > 0)
    .map((s) => {
      const frac = total > 0 ? s.value / total : 0
      const len = Math.max(0.001, frac * c - inset)
      const arc = { ...s, len, offset: offset + inset / 2, rest: c - len }
      offset += frac * c
      return arc
    })

  return (
    <div className={cn('relative flex-none', className)} style={{ width: size, height: size }}>
      <svg width={size} height={size} style={{ transform: 'rotate(-90deg)' }} aria-hidden>
        <circle
          cx={size / 2}
          cy={size / 2}
          r={r}
          fill="none"
          stroke="var(--v2-surface-3)"
          strokeWidth={thickness}
        />
        {arcs.map((a) => (
          <circle
            key={`${id}-${a.key}`}
            cx={size / 2}
            cy={size / 2}
            r={r}
            fill="none"
            stroke={a.color}
            strokeWidth={thickness}
            strokeLinecap="round"
            strokeDasharray={`${a.len} ${a.rest}`}
            strokeDashoffset={-a.offset}
          />
        ))}
      </svg>
      {(centerLabel || centerValue) && (
        <div className="absolute inset-0 flex flex-col items-center justify-center gap-0.5">
          {centerValue && (
            <span data-amount="v2" className="v2-num text-[15px] font-medium leading-none">
              {centerValue}
            </span>
          )}
          {centerLabel && <span className="v2-micro leading-none">{centerLabel}</span>}
        </div>
      )}
    </div>
  )
}

export function DonutLegend({
  slices,
  format,
  total,
  className,
}: {
  slices: DonutSlice[]
  format: (v: number) => string
  total: number
  className?: string
}) {
  return (
    <ul className={cn('flex min-w-0 flex-1 flex-col gap-2', className)}>
      {slices.map((s) => {
        const pct = total > 0 ? Math.round((s.value / total) * 100) : 0
        return (
          <li key={s.key} className="flex items-center gap-2.5">
            <i
              aria-hidden
              className="h-2 w-2 flex-none rounded-full"
              style={{ background: s.color }}
            />
            <span className="v2-sub min-w-0 flex-1 truncate">{s.label}</span>
            <span data-amount="v2" className="v2-num text-[12.5px] font-medium">
              {format(s.value)}
            </span>
            <span className="v2-num w-8 text-right text-[11px] text-[var(--v2-text-3)]">
              {pct}%
            </span>
          </li>
        )
      })}
    </ul>
  )
}
