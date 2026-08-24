'use client'

import { useRef, useState } from 'react'
import { cn } from '../../../lib/utils'

export interface SwipeAction {
  key: string
  label: string
  icon: React.ReactNode
  background: string
  onSelect: () => void
}

const SNAP_RATIO = 0.4

/**
 * Reveal-on-swipe row.
 *
 * The gesture only takes over once horizontal movement clearly beats vertical
 * — `locked` is decided on the first few pixels and then held for the rest of
 * the drag. Without that, every attempt to scroll the list past a row would
 * nudge it open, which is the classic way home-rolled swipe rows ruin a list.
 */
export function SwipeRow({
  actions,
  children,
  className,
}: {
  actions: SwipeAction[]
  children: React.ReactNode
  className?: string
}) {
  const surfaceRef = useRef<HTMLDivElement>(null)
  const [open, setOpen] = useState(false)
  const [dragging, setDragging] = useState(false)
  const drag = useRef<{ x: number; y: number; locked: 'x' | 'y' | null; dx: number } | null>(null)

  const width = actions.length * 76
  if (actions.length === 0) return <div className={className}>{children}</div>

  const move = (dx: number) => {
    const el = surfaceRef.current
    if (el) el.style.transform = `translateX(${dx}px)`
  }

  const settle = (openNow: boolean) => {
    setOpen(openNow)
    move(openNow ? -width : 0)
  }

  return (
    <div className={cn('v2-swipe', className)}>
      {/*
        * Mounted only while the row is open or moving. Left permanently behind
        * the surface, a one-pixel rounding seam between rows let the red delete
        * background show through as a stray line across the list.
        */}
      <div
        className="v2-swipe-actions"
        aria-hidden={!open}
        style={{ visibility: open || dragging ? 'visible' : 'hidden' }}
      >
        {actions.map((a) => (
          <button
            key={a.key}
            type="button"
            tabIndex={open ? 0 : -1}
            onClick={() => {
              settle(false)
              a.onSelect()
            }}
            className="v2-swipe-action flex-col"
            style={{ background: a.background }}
          >
            {a.icon}
            <span>{a.label}</span>
          </button>
        ))}
      </div>

      <div
        ref={surfaceRef}
        className="v2-swipe-surface"
        data-dragging={dragging || undefined}
        style={{ transform: open ? `translateX(${-width}px)` : undefined }}
        onPointerDown={(e) => {
          if (e.pointerType === 'mouse' && e.button !== 0) return
          drag.current = { x: e.clientX, y: e.clientY, locked: null, dx: open ? -width : 0 }
        }}
        onPointerMove={(e) => {
          const d = drag.current
          if (!d) return
          const dx = e.clientX - d.x
          const dy = e.clientY - d.y
          if (d.locked === null) {
            if (Math.abs(dx) < 8 && Math.abs(dy) < 8) return
            d.locked = Math.abs(dx) > Math.abs(dy) ? 'x' : 'y'
            if (d.locked === 'x') {
              setDragging(true)
              e.currentTarget.setPointerCapture(e.pointerId)
            }
          }
          if (d.locked !== 'x') return
          const base = open ? -width : 0
          // Rubber-band past the fully-open position and past zero, so the row
          // never detaches from the finger but also never overshoots freely.
          let next = base + dx
          if (next > 0) next /= 4
          if (next < -width) next = -width + (next + width) / 4
          d.dx = next
          move(next)
        }}
        onPointerUp={(e) => {
          const d = drag.current
          drag.current = null
          setDragging(false)
          if (!d || d.locked !== 'x') return
          e.currentTarget.releasePointerCapture?.(e.pointerId)
          settle(d.dx < -width * SNAP_RATIO)
        }}
        onPointerCancel={() => {
          drag.current = null
          setDragging(false)
          settle(open)
        }}
      >
        {children}
      </div>
    </div>
  )
}
