'use client'
import { Eye, EyeOff } from 'lucide-react'
import { useT } from '../i18n/context'
import { cn } from '../lib/utils'
import { usePrivacy } from './context'

interface PrivacyToggleProps {
  variant?: 'sidebar' | 'compact'
  className?: string
}

/**
 * Toggles privacy mode (hide amounts). Matches ThemeToggle's variant API so
 * it slots into the sidebar footer and mobile top bar without visual drift.
 */
export function PrivacyToggle({ variant = 'sidebar', className }: PrivacyToggleProps) {
  const { hidden, toggle } = usePrivacy()
  const t = useT()
  const label = hidden ? t('privacy.show', 'Show amounts') : t('privacy.hide', 'Hide amounts')
  const Icon = hidden ? EyeOff : Eye

  if (variant === 'compact') {
    return (
      <button
        type="button"
        onClick={toggle}
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
      onClick={toggle}
      aria-label={label}
      className={cn(
        'flex w-full items-center gap-3 rounded-md px-3 py-2 text-sm text-sidebar-foreground/70 transition-colors hover:bg-sidebar-accent hover:text-sidebar-accent-foreground',
        className,
      )}
    >
      <Icon className="h-4 w-4" />
      <span>{label}</span>
    </button>
  )
}
