'use client'

import { useRef } from 'react'

/**
 * Set of keys that have already played their entrance animation in the
 * current SPA session. Lives at module scope so it survives client-side
 * navigations (which remount the chart components) but resets on a full
 * page reload (which re-evaluates the module).
 */
const played = new Set<string>()

/**
 * Returns `true` the first time a given `key` mounts in the current tab
 * session, `false` on every subsequent remount. Use it to gate one-shot
 * entrance animations so they don't replay every time the user navigates
 * back to a view.
 *
 * ```tsx
 * const shouldAnimate = usePlayOnce('dashboard:patrimony')
 * <Area isAnimationActive={shouldAnimate} ... />
 * ```
 */
export function usePlayOnce(key: string): boolean {
  // Freeze the decision at first render so the value stays stable across
  // re-renders within the same mount — otherwise StrictMode's double-render
  // or any parent re-render would flip us from true to false mid-animation.
  const decidedRef = useRef<boolean | null>(null)
  if (decidedRef.current === null) {
    decidedRef.current = !played.has(key)
    played.add(key)
  }
  return decidedRef.current
}
