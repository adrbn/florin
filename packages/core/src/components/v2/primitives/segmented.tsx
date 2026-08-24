'use client'

import { useCallback, useEffect, useLayoutEffect, useRef, useState } from 'react'
import { cn } from '../../../lib/utils'

export interface SegmentedOption<T extends string> {
  value: T
  label: string
}

/**
 * Sliding-pill segmented control.
 *
 * The thumb is measured rather than assumed to be `100 / n` percent wide:
 * "Abonnements" and "Vue" cannot share a track fairly, and equal thirds would
 * either clip the long label or waste half the bar on the short one. A
 * ResizeObserver re-measures on rotation and font swap, so the pill never
 * drifts off its label.
 */
export function Segmented<T extends string>({
  options,
  value,
  onChange,
  className,
  scrollable = false,
}: {
  options: ReadonlyArray<SegmentedOption<T>>
  value: T
  onChange: (v: T) => void
  className?: string
  /** Let items size to content and scroll horizontally instead of splitting evenly. */
  scrollable?: boolean
}) {
  const trackRef = useRef<HTMLDivElement>(null)
  const itemRefs = useRef<Array<HTMLButtonElement | null>>([])
  const [thumb, setThumb] = useState<{ x: number; w: number } | null>(null)
  const [atEnd, setAtEnd] = useState(true)

  const activeIndex = Math.max(
    0,
    options.findIndex((o) => o.value === value),
  )

  const measure = useCallback(() => {
    const track = trackRef.current
    const item = itemRefs.current[activeIndex]
    if (!track || !item) return
    setThumb({ x: item.offsetLeft - 3, w: item.offsetWidth })
  }, [activeIndex])

  // Layout effect so the thumb is already in place on first paint — a pill
  // that animates in from x=0 on mount reads as a glitch.
  useLayoutEffect(measure, [measure, options.length])

  useEffect(() => {
    const track = trackRef.current
    if (!track || typeof ResizeObserver === 'undefined') return
    const ro = new ResizeObserver(measure)
    // Observe the items too, not just the track. A web font swapping in after
    // hydration changes item widths while the track stays exactly as wide as
    // it was — observing only the track leaves the thumb sized for the
    // fallback font, which is how it ends up half a label wide.
    ro.observe(track)
    for (const el of itemRefs.current) if (el) ro.observe(el)
    return () => ro.disconnect()
  }, [measure, options.length])

  // Keep the active item visible in the scrollable variant.
  useEffect(() => {
    if (!scrollable) return
    itemRefs.current[activeIndex]?.scrollIntoView({
      inline: 'center',
      block: 'nearest',
      behavior: 'smooth',
    })
  }, [activeIndex, scrollable])

  // Drop the trailing fade once there is nothing left to scroll to.
  useEffect(() => {
    const track = trackRef.current
    if (!scrollable || !track) return
    const check = () =>
      setAtEnd(track.scrollLeft + track.clientWidth >= track.scrollWidth - 2)
    check()
    track.addEventListener('scroll', check, { passive: true })
    return () => track.removeEventListener('scroll', check)
  }, [scrollable, options.length])

  return (
    <div
      ref={trackRef}
      role="tablist"
      data-at-end={scrollable ? atEnd : undefined}
      className={cn(
        'v2-seg',
        scrollable &&
          'v2-seg-scroll overflow-x-auto [scrollbar-width:none] [&::-webkit-scrollbar]:hidden',
        className,
      )}
    >
      {thumb && (
        <span
          aria-hidden
          className="v2-seg-thumb"
          style={{ width: thumb.w, transform: `translateX(${thumb.x}px)` }}
        />
      )}
      {options.map((o, i) => (
        <button
          key={o.value}
          ref={(el) => {
            itemRefs.current[i] = el
          }}
          type="button"
          role="tab"
          aria-selected={o.value === value}
          data-active={o.value === value}
          onClick={() => onChange(o.value)}
          className={cn('v2-seg-item truncate', scrollable && 'flex-none px-3.5')}
        >
          {o.label}
        </button>
      ))}
    </div>
  )
}
