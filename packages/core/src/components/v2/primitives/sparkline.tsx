'use client'

import { useCallback, useEffect, useId, useMemo, useRef, useState } from 'react'
import { clamp } from '../lib/format'
import { cn } from '../../../lib/utils'

export interface SparkPoint {
  /** Any monotonically increasing key — an epoch ms or an index. */
  x: number
  y: number
  /** Forward-looking points render dashed and unfilled. */
  projected?: boolean
  /** Carried through to the scrub callback so the parent can label the point. */
  label?: string
}

/**
 * Monotone cubic interpolation (Fritsch–Carlson).
 *
 * A plain Catmull–Rom spline overshoots between points, which on a net-worth
 * curve invents dips that never happened — unacceptable on a chart people read
 * as fact. Monotone tangents are clamped so the curve can never leave the
 * interval between two consecutive samples.
 */
function monotonePath(pts: Array<{ x: number; y: number }>): string {
  const n = pts.length
  if (n === 0) return ''
  if (n === 1) return `M ${pts[0]!.x} ${pts[0]!.y}`
  if (n === 2) return `M ${pts[0]!.x} ${pts[0]!.y} L ${pts[1]!.x} ${pts[1]!.y}`

  const dx: number[] = []
  const dy: number[] = []
  const slope: number[] = []
  for (let i = 0; i < n - 1; i++) {
    const h = pts[i + 1]!.x - pts[i]!.x
    dx.push(h)
    dy.push(pts[i + 1]!.y - pts[i]!.y)
    slope.push(h === 0 ? 0 : (pts[i + 1]!.y - pts[i]!.y) / h)
  }

  const m: number[] = new Array(n).fill(0)
  m[0] = slope[0]!
  m[n - 1] = slope[n - 2]!
  for (let i = 1; i < n - 1; i++) {
    const s0 = slope[i - 1]!
    const s1 = slope[i]!
    // A sign change is a local extremum: flatten the tangent so the curve
    // turns around exactly at the sample instead of sailing past it.
    m[i] = s0 * s1 <= 0 ? 0 : (s0 + s1) / 2
  }
  for (let i = 0; i < n - 1; i++) {
    if (slope[i] === 0) {
      m[i] = 0
      m[i + 1] = 0
      continue
    }
    const a = m[i]! / slope[i]!
    const b = m[i + 1]! / slope[i]!
    const s = a * a + b * b
    if (s > 9) {
      const tau = 3 / Math.sqrt(s)
      m[i] = tau * a * slope[i]!
      m[i + 1] = tau * b * slope[i]!
    }
  }

  let d = `M ${pts[0]!.x} ${pts[0]!.y}`
  for (let i = 0; i < n - 1; i++) {
    const h = dx[i]! / 3
    d += ` C ${pts[i]!.x + h} ${pts[i]!.y + m[i]! * h}, ${pts[i + 1]!.x - h} ${
      pts[i + 1]!.y - m[i + 1]! * h
    }, ${pts[i + 1]!.x} ${pts[i + 1]!.y}`
  }
  return d
}

export interface SparklineProps {
  data: SparkPoint[]
  height?: number
  color?: string
  /** Fill the area under the realized part of the curve. */
  fill?: boolean
  /** Dotted horizontal rule at the first value — the "since then" reference. */
  baseline?: boolean
  /** Called with the scrubbed point, or null when the finger lifts. */
  onScrub?: (point: SparkPoint | null, index: number | null) => void
  className?: string
  ariaLabel?: string
}

/**
 * The hero chart: a 1px line, a soft gradient, no grid, no axes — and a scrub
 * that rewrites the headline figure as the finger moves.
 *
 * Width comes from a ResizeObserver rather than a viewBox stretch: scaling a
 * viewBox to fit would scale the stroke with it, and a 1px line that becomes
 * 1.4px on a wide phone is exactly the kind of softness this design is trying
 * to avoid.
 */
export function Sparkline({
  data,
  height = 132,
  color = 'var(--v2-accent)',
  fill = true,
  baseline = false,
  onScrub,
  className,
  ariaLabel,
}: SparklineProps) {
  const wrapRef = useRef<HTMLDivElement>(null)
  const [width, setWidth] = useState(0)
  const [active, setActive] = useState<number | null>(null)
  const gradId = useId().replace(/:/g, '')

  useEffect(() => {
    const el = wrapRef.current
    if (!el) return
    setWidth(el.clientWidth)
    if (typeof ResizeObserver === 'undefined') return
    const ro = new ResizeObserver(([entry]) => {
      if (entry) setWidth(entry.contentRect.width)
    })
    ro.observe(el)
    return () => ro.disconnect()
  }, [])

  const geom = useMemo(() => {
    if (data.length === 0 || width <= 0) return null
    const padY = 10
    const xs = data.map((d) => d.x)
    const ys = data.map((d) => d.y)
    const minX = Math.min(...xs)
    const maxX = Math.max(...xs)
    const minY = Math.min(...ys)
    const maxY = Math.max(...ys)
    const spanX = maxX - minX || 1
    // A flat series must not collapse onto a single row of pixels; give it a
    // nominal span so it draws as a centred horizontal line.
    const spanY = maxY - minY || Math.max(1, Math.abs(maxY) * 0.02)

    const sx = (x: number) => ((x - minX) / spanX) * width
    const sy = (y: number) => height - padY - ((y - minY) / spanY) * (height - padY * 2)

    const screen = data.map((d) => ({ x: sx(d.x), y: sy(d.y) }))
    const firstProjected = data.findIndex((d) => d.projected)
    const splitAt = firstProjected === -1 ? data.length : firstProjected

    const realized = screen.slice(0, splitAt)
    // Overlap by one point so the dashed segment starts exactly on the solid
    // one instead of leaving a visible gap at the seam.
    const projected = splitAt > 0 ? screen.slice(splitAt - 1) : screen.slice(splitAt)

    const linePath = monotonePath(realized)
    const projPath = projected.length > 1 ? monotonePath(projected) : ''
    const areaPath =
      realized.length > 1
        ? `${linePath} L ${realized[realized.length - 1]!.x} ${height} L ${realized[0]!.x} ${height} Z`
        : ''

    return { screen, linePath, projPath, areaPath, sy, baseY: sy(ys[0]!) }
  }, [data, width, height])

  const pick = useCallback(
    (clientX: number) => {
      const el = wrapRef.current
      if (!el || !geom || data.length === 0) return
      const rect = el.getBoundingClientRect()
      const x = clamp(clientX - rect.left, 0, rect.width)
      // Nearest sample, not the one to the left — the dot should snap to
      // whichever point the finger is actually closest to.
      let best = 0
      let bestD = Infinity
      for (let i = 0; i < geom.screen.length; i++) {
        const d = Math.abs(geom.screen[i]!.x - x)
        if (d < bestD) {
          bestD = d
          best = i
        }
      }
      setActive(best)
      onScrub?.(data[best]!, best)
    },
    [data, geom, onScrub],
  )

  const release = useCallback(() => {
    setActive(null)
    onScrub?.(null, null)
  }, [onScrub])

  if (data.length === 0) {
    return <div ref={wrapRef} className={cn('w-full', className)} style={{ height }} />
  }

  const dot = active !== null && geom ? geom.screen[active] : null

  return (
    <div
      ref={wrapRef}
      className={cn('relative w-full touch-none select-none', className)}
      style={{ height }}
      role="img"
      aria-label={ariaLabel}
      onPointerDown={(e) => {
        ;(e.currentTarget as HTMLElement).setPointerCapture(e.pointerId)
        pick(e.clientX)
      }}
      onPointerMove={(e) => {
        if (e.buttons === 0 && e.pointerType === 'mouse') return
        pick(e.clientX)
      }}
      onPointerUp={release}
      onPointerCancel={release}
      onPointerLeave={release}
    >
      {geom && width > 0 && (
        <svg width={width} height={height} className="block overflow-visible">
          <defs>
            <linearGradient id={`g${gradId}`} x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor={color} stopOpacity="var(--v2-spark-fill, 0.22)" />
              <stop offset="100%" stopColor={color} stopOpacity="0" />
            </linearGradient>
          </defs>

          {baseline && geom.baseY > 14 && geom.baseY < height - 14 && (
            <line
              x1={0}
              x2={width}
              y1={geom.baseY}
              y2={geom.baseY}
              stroke="var(--v2-text-3)"
              strokeWidth={1}
              strokeDasharray="2 4"
              opacity={0.5}
            />
          )}

          {fill && geom.areaPath && <path d={geom.areaPath} fill={`url(#g${gradId})`} />}

          {geom.projPath && (
            <path
              d={geom.projPath}
              fill="none"
              stroke={color}
              strokeWidth={1.25}
              strokeDasharray="3 4"
              opacity={0.55}
              strokeLinecap="round"
            />
          )}

          <path
            d={geom.linePath}
            fill="none"
            stroke={color}
            strokeWidth={1.5}
            strokeLinecap="round"
            strokeLinejoin="round"
            vectorEffect="non-scaling-stroke"
          />

          {dot && (
            <g>
              <line
                x1={dot.x}
                x2={dot.x}
                y1={0}
                y2={height}
                stroke="var(--v2-line-strong)"
                strokeWidth={1}
              />
              <circle cx={dot.x} cy={dot.y} r={7} fill={color} opacity={0.18} />
              <circle
                cx={dot.x}
                cy={dot.y}
                r={3.5}
                fill="var(--v2-bg)"
                stroke={color}
                strokeWidth={2}
              />
            </g>
          )}
        </svg>
      )}
    </div>
  )
}
