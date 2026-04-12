'use client'

import { Moon, Sun } from 'lucide-react'
import { useTheme } from 'next-themes'
import { useEffect, useState } from 'react'
import { cn } from '../../lib/utils'

interface ThemeToggleProps {
  /**
   * Visual variant:
   *   - `sidebar` — full-width row that matches the sign-out button in the
   *     desktop sidebar footer.
   *   - `compact` — icon-only square button for tight spots like the
   *     mobile top bar.
   */
  variant?: 'sidebar' | 'compact'
  className?: string
}

/**
 * Light/dark switcher. Resolves the current theme via `next-themes` and
 * flips between `light` and `dark` explicitly — we don't expose the
 * `system` option in the UI because the user asked for an explicit
 * night-mode switch, not a tri-state selector.
 *
 * A `mounted` guard avoids the hydration mismatch you'd otherwise get
 * because `resolvedTheme` is only known on the client.
 */
export function ThemeToggle({ variant = 'sidebar', className }: ThemeToggleProps) {
  const { resolvedTheme, setTheme } = useTheme()
  const [mounted, setMounted] = useState(false)

  useEffect(() => {
    setMounted(true)
  }, [])

  const isDark = mounted && resolvedTheme === 'dark'
  const next = isDark ? 'light' : 'dark'
  const label = isDark ? 'Switch to light mode' : 'Switch to dark mode'
  const Icon = isDark ? Sun : Moon

  if (variant === 'compact') {
    return (
      <button
        type="button"
        onClick={() => setTheme(next)}
        aria-label={label}
        title={label}
        className={cn(
          'flex items-center justify-center rounded-md px-2 py-1 text-sidebar-foreground/70 transition-colors hover:bg-sidebar-accent hover:text-sidebar-accent-foreground',
          className,
        )}
      >
        <Icon className="h-3.5 w-3.5" />
      </button>
    )
  }

  return (
    <button
      type="button"
      onClick={() => setTheme(next)}
      aria-label={label}
      className={cn(
        'flex w-full items-center gap-3 rounded-md px-3 py-2 text-sm text-sidebar-foreground/70 transition-colors hover:bg-sidebar-accent hover:text-sidebar-accent-foreground',
        className,
      )}
    >
      <Icon className="h-4 w-4" />
      <span>{isDark ? 'Light mode' : 'Dark mode'}</span>
    </button>
  )
}
