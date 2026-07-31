'use client'

import { useCallback, useEffect, useLayoutEffect, useState } from 'react'
import { useT } from '../../i18n/context'

/** Bump to re-run the tour for everyone after a meaningful dashboard change. */
export const TOUR_SEEN_KEY = 'florin:tour:dashboard:v1'

interface TourStep {
  /** Matches a `data-tour="…"` attribute somewhere on the dashboard. */
  target: string
  title: string
  body: string
}

interface DashboardTourProps {
  /** Tour only makes sense once there's an account to look at. */
  enabled: boolean
  /** Set by the parent to force a replay, bypassing the "already seen" flag. */
  replayToken?: number
  onClose?: () => void
}

interface Rect {
  top: number
  left: number
  width: number
  height: number
}

const PAD = 8
const TOOLTIP_W = 300
const GAP = 12

function readRect(target: string): Rect | null {
  if (typeof document === 'undefined') return null
  const el = document.querySelector(`[data-tour="${target}"]`)
  if (!el) return null
  const r = el.getBoundingClientRect()
  // A zero-sized box means the element is present but not laid out (collapsed
  // container, still-suspended subtree) — treat it as absent rather than
  // spotlighting a 0×0 point.
  if (r.width < 1 || r.height < 1) return null
  return { top: r.top, left: r.left, width: r.width, height: r.height }
}

/**
 * A short spotlight tour of the dashboard, shown once after the user's first
 * account exists. Dims the page, cuts a hole around one element at a time and
 * explains it.
 *
 * Deliberately defensive: any step whose target isn't on the page (a card that
 * only renders with data, a layout that dropped it at this breakpoint) is
 * skipped rather than pointing at nothing, and the whole overlay is
 * `position: fixed` so it can never disturb the dashboard's layout.
 */
export function DashboardTour({ enabled, replayToken = 0, onClose }: DashboardTourProps) {
  const t = useT()
  const [steps, setSteps] = useState<TourStep[]>([])
  const [index, setIndex] = useState(0)
  const [rect, setRect] = useState<Rect | null>(null)
  const [open, setOpen] = useState(false)

  const allSteps: TourStep[] = [
    {
      target: 'checklist',
      title: t('tour.checklistTitle', 'Your first steps'),
      body: t('tour.checklistBody', 'This checklist tracks what is left to set up. It disappears once you are done.'),
    },
    {
      target: 'kpis',
      title: t('tour.kpisTitle', 'Your key figures'),
      body: t('tour.kpisBody', 'Net worth, what you spent this month, what is left, and how long your savings would last.'),
    },
    {
      target: 'charts',
      title: t('tour.chartsTitle', 'Your trends'),
      body: t('tour.chartsBody', 'How your wealth evolves over time, and income versus spending month by month.'),
    },
    {
      target: 'sync',
      title: t('tour.syncTitle', 'Refresh your data'),
      body: t('tour.syncBody', 'Fetch the latest transactions from your bank whenever you like — it also runs on its own.'),
    },
  ]

  // Decide whether to run, and drop steps whose target is missing. Runs after
  // paint so Suspense boundaries have resolved and the cards actually exist.
  useEffect(() => {
    if (!enabled) return
    let seen = false
    try {
      seen = window.localStorage.getItem(TOUR_SEEN_KEY) === '1'
    } catch {
      // Storage unavailable — show it, worst case it repeats.
    }
    if (seen && replayToken === 0) return

    const timer = window.setTimeout(() => {
      const available = allSteps.filter((s) => readRect(s.target) !== null)
      if (available.length === 0) return
      setSteps(available)
      setIndex(0)
      setOpen(true)
    }, 600)
    return () => window.clearTimeout(timer)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [enabled, replayToken])

  const current = steps[index]

  const reposition = useCallback(() => {
    if (!current) return
    setRect(readRect(current.target))
  }, [current])

  // useLayoutEffect so the spotlight lands on the right box before paint,
  // avoiding a visible jump when moving between steps.
  useLayoutEffect(() => {
    if (!open || !current) return
    const el = document.querySelector(`[data-tour="${current.target}"]`)
    el?.scrollIntoView({ block: 'nearest', behavior: 'smooth' })
    reposition()
  }, [open, current, reposition])

  useEffect(() => {
    if (!open) return
    window.addEventListener('resize', reposition)
    window.addEventListener('scroll', reposition, true)
    return () => {
      window.removeEventListener('resize', reposition)
      window.removeEventListener('scroll', reposition, true)
    }
  }, [open, reposition])

  const finish = useCallback(() => {
    setOpen(false)
    try {
      window.localStorage.setItem(TOUR_SEEN_KEY, '1')
    } catch {
      // Non-fatal.
    }
    onClose?.()
  }, [onClose])

  const next = useCallback(() => {
    setIndex((i) => {
      if (i + 1 >= steps.length) {
        finish()
        return i
      }
      return i + 1
    })
  }, [steps.length, finish])

  useEffect(() => {
    if (!open) return
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') finish()
      if (e.key === 'ArrowRight' || e.key === 'Enter') next()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open, finish, next])

  if (!open || !current) return null
  // The target was there when we built the step list but has since gone (a
  // Suspense boundary swapped it, the user resized into a layout that drops
  // it). Move on rather than sitting on an invisible overlay the user can't
  // dismiss.
  if (!rect) {
    queueMicrotask(next)
    return null
  }

  const holeTop = rect.top - PAD
  const holeLeft = rect.left - PAD
  const holeW = rect.width + PAD * 2
  const holeH = rect.height + PAD * 2

  // Prefer below the highlighted box; flip above when it would run off-screen.
  const spaceBelow = window.innerHeight - (holeTop + holeH)
  const placeBelow = spaceBelow > 170
  const tooltipTop = placeBelow ? holeTop + holeH + GAP : Math.max(GAP, holeTop - 170 - GAP)
  const tooltipLeft = Math.min(
    Math.max(GAP, holeLeft),
    Math.max(GAP, window.innerWidth - TOOLTIP_W - GAP),
  )

  return (
    <div className="fixed inset-0 z-[100]" role="dialog" aria-modal="true" aria-label={current.title}>
      {/* Dim + spotlight: one element, the dimming is its outer box-shadow so
          the hole is genuinely transparent and the highlighted card stays
          readable underneath. */}
      <div
        className="pointer-events-none absolute rounded-xl ring-2 ring-primary transition-all duration-300"
        style={{
          top: holeTop,
          left: holeLeft,
          width: holeW,
          height: holeH,
          boxShadow: '0 0 0 9999px rgb(0 0 0 / 0.6)',
        }}
      />
      {/* Click-catcher: advances the tour, and keeps clicks off the page. */}
      <button
        type="button"
        aria-label={t('tour.next', 'Next')}
        onClick={next}
        className="absolute inset-0 h-full w-full cursor-default"
        style={{ background: 'transparent' }}
      />

      <div
        className="absolute w-[300px] rounded-xl border border-border bg-popover p-4 text-popover-foreground shadow-xl transition-all duration-300"
        style={{ top: tooltipTop, left: tooltipLeft }}
      >
        <p className="text-sm font-semibold">{current.title}</p>
        <p className="mt-1 text-xs leading-relaxed text-muted-foreground">{current.body}</p>
        <div className="mt-3 flex items-center justify-between gap-2">
          <span className="text-[11px] tabular-nums text-muted-foreground">
            {index + 1}/{steps.length}
          </span>
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={finish}
              className="rounded-md px-2 py-1 text-xs text-muted-foreground transition-colors hover:text-foreground"
            >
              {t('tour.skip', 'Skip')}
            </button>
            <button
              type="button"
              onClick={next}
              className="rounded-md bg-primary px-3 py-1.5 text-xs font-medium text-primary-foreground shadow-sm transition-colors hover:bg-primary/90"
            >
              {index + 1 >= steps.length ? t('tour.done', 'Got it') : t('tour.next', 'Next')}
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}
