'use client'

import { LogOut } from 'lucide-react'
import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { signOut } from 'next-auth/react'
import { ThemeToggle } from '../theme/theme-toggle'
import { PrivacyToggle } from '../../privacy/toggle'
import { useT } from '../../i18n/context'
import { cn } from '../../lib/utils'
import { isLinkActive, type NavBadges, visibleNavLinks } from './nav-links'

interface MobileTopBarProps {
  badges?: NavBadges
}

/**
 * Mobile-only navigation bar that replaces the desktop sidebar below `md`.
 *
 * Layout:
 *   ┌───────────────────────────────────────────────────┐
 *   │ Florin                                 [sign out] │
 *   ├───────────────────────────────────────────────────┤
 *   │ [Dash] [Review] [Txns] [Accounts] [Cats] …        │  ← horizontal scroll
 *   └───────────────────────────────────────────────────┘
 *
 * We keep it sticky at the top so it never steals vertical space from the
 * content below — and we use horizontal scroll instead of a burger menu so
 * every destination is one tap away, matching the feeling of a tab bar.
 */
export function MobileTopBar({ badges }: MobileTopBarProps = {}) {
  const pathname = usePathname()
  const links = visibleNavLinks(badges)
  const t = useT()
  return (
    <header className="sticky top-0 z-30 flex shrink-0 flex-col border-b bg-sidebar/95 text-sidebar-foreground backdrop-blur supports-[backdrop-filter]:bg-sidebar/80 md:hidden">
      <div className="flex items-center justify-between px-4 py-2.5">
        <div className="flex items-center gap-2">
          <span aria-hidden className="h-1.5 w-1.5 rounded-full bg-sidebar-primary" />
          <span
            className="text-xl leading-none"
            style={{ fontFamily: "'Tuaf', ui-sans-serif, system-ui, sans-serif", letterSpacing: '-0.02em' }}
          >
            Florin
          </span>
        </div>
        <div className="flex items-center gap-1">
          <PrivacyToggle variant="compact" />
          <ThemeToggle variant="compact" />
          <button
            type="button"
            onClick={() => signOut({ callbackUrl: '/login' })}
            className="flex items-center gap-1 rounded-md px-2 py-1 text-[11px] text-sidebar-foreground/70 transition-colors hover:bg-sidebar-accent hover:text-sidebar-accent-foreground"
            aria-label={t('shell.signOut', 'Sign out')}
          >
            <LogOut className="h-3.5 w-3.5" />
          </button>
        </div>
      </div>
      <nav
        aria-label="Primary"
        className="-mb-px flex gap-1 overflow-x-auto px-2 pb-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
      >
        {links.map((l) => {
          const Icon = l.icon
          const active = isLinkActive(l.href, pathname)
          const badgeValue = l.badgeKey ? badges?.[l.badgeKey] : undefined
          const showBadge = typeof badgeValue === 'number' && badgeValue > 0
          return (
            <Link
              key={l.href}
              href={l.href as never}
              aria-current={active ? 'page' : undefined}
              className={cn(
                'relative flex shrink-0 items-center gap-1.5 rounded-md px-2.5 py-1.5 text-[12px] font-medium transition-colors',
                active
                  ? 'bg-sidebar-primary text-sidebar-primary-foreground'
                  : 'text-sidebar-foreground/70 hover:bg-sidebar-accent hover:text-sidebar-accent-foreground',
              )}
            >
              <Icon className="h-3.5 w-3.5" />
              <span>{t(l.labelKey, l.label)}</span>
              {showBadge && (
                <span
                  className={cn(
                    'inline-flex min-w-[1.1rem] items-center justify-center rounded-full px-1 text-[9px] font-semibold',
                    active
                      ? 'bg-sidebar-primary-foreground/20 text-sidebar-primary-foreground'
                      : 'bg-amber-500/20 text-amber-700 dark:text-amber-300',
                  )}
                >
                  {badgeValue}
                </span>
              )}
            </Link>
          )
        })}
      </nav>
    </header>
  )
}
