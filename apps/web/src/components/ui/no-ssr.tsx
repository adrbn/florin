'use client'

import { useEffect, useState, type ReactNode } from 'react'

/**
 * Render children only after the component has mounted on the client.
 *
 * Recharts' ResponsiveContainer measures its parent via the browser DOM, so
 * during server-side rendering it has no width/height and emits warnings like
 * `The width(-1) and height(-1) of chart should be greater than 0`. Wrapping
 * the chart in <NoSSR> defers the actual render until hydration, when the
 * parent has real dimensions.
 */
export function NoSSR({ children, fallback = null }: { children: ReactNode; fallback?: ReactNode }) {
  const [mounted, setMounted] = useState(false)
  useEffect(() => {
    setMounted(true)
  }, [])
  return <>{mounted ? children : fallback}</>
}
