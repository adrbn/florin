'use client'

import { useEffect, useRef, useState } from 'react'

export interface ScrollState {
  /** True once the page has moved past `stickAt` — the header goes glassy. */
  stuck: boolean
  /** True while the user is scrolling down and past `hideAfter`. */
  hidden: boolean
}

/**
 * Direction-aware scroll state for the sticky header and the floating tab bar.
 *
 * The `IDLE_PX` deadband is what stops the tab bar strobing: without it, the
 * one-or-two-pixel jitter of a momentum scroll (and iOS's rubber band at the
 * extremes) flips the direction several times a second.
 */
const IDLE_PX = 6

export function useScrollChrome({ stickAt = 12, hideAfter = 140 } = {}): ScrollState {
  const [state, setState] = useState<ScrollState>({ stuck: false, hidden: false })
  const last = useRef(0)
  const frame = useRef(0)

  useEffect(() => {
    last.current = window.scrollY

    const read = () => {
      frame.current = 0
      const y = window.scrollY
      const delta = y - last.current
      if (Math.abs(delta) < IDLE_PX) {
        setState((s) => (s.stuck === y > stickAt ? s : { ...s, stuck: y > stickAt }))
        return
      }
      last.current = y
      const goingDown = delta > 0
      setState((s) => {
        const stuck = y > stickAt
        const hidden = goingDown && y > hideAfter
        return s.stuck === stuck && s.hidden === hidden ? s : { stuck, hidden }
      })
    }

    const onScroll = () => {
      if (frame.current) return
      frame.current = window.requestAnimationFrame(read)
    }

    window.addEventListener('scroll', onScroll, { passive: true })
    read()
    return () => {
      window.removeEventListener('scroll', onScroll)
      if (frame.current) window.cancelAnimationFrame(frame.current)
    }
  }, [stickAt, hideAfter])

  return state
}
