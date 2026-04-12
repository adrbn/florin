'use client'

import { LogOut } from 'lucide-react'
import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { signOut } from 'next-auth/react'
import { ThemeToggle } from '../theme/theme-toggle'
import { cn } from '../../lib/utils'
import { isLinkActive, type NavBadges, visibleNavLinks } from './nav-links'

interface SidebarProps {
  badges?: NavBadges
}

/**
 * Desktop sidebar. Hidden on viewports below `md` — the mobile top bar
 * component takes over there. Keeping this desktop-only lets us use a
 * stable 15rem rail without stealing horizontal space on phones.
 */
export function Sidebar({ badges }: SidebarProps = {}) {
  const pathname = usePathname()
  const links = visibleNavLinks(badges)
  return (
    <aside className="hidden w-60 shrink-0 flex-col border-r bg-sidebar text-sidebar-foreground md:flex">
      <div className="flex items-center gap-2 px-6 py-5">
        <span
          aria-hidden
          className="h-2 w-2 rounded-full bg-sidebar-primary shadow-[0_0_0_3px_hsl(var(--sidebar-primary)/0.15)]"
        />
        <h2 className="text-lg font-semibold tracking-tight">Florin</h2>
      </div>
      <nav className="flex-1 space-y-0.5 px-3">
        {links.map((l) => {
          const Icon = l.icon
          const active = isLinkActive(l.href, pathname)
          const badgeValue = l.badgeKey ? badges?.[l.badgeKey] : undefined
          const showBadge = typeof badgeValue === 'number' && badgeValue > 0
          return (
            <Link
              key={l.href}
              href={l.href as never}
              className={cn(
                'flex items-center justify-between gap-3 rounded-md px-3 py-2 text-sm transition-colors',
                active
                  ? 'bg-sidebar-primary text-sidebar-primary-foreground'
                  : 'text-sidebar-foreground/70 hover:bg-sidebar-accent hover:text-sidebar-accent-foreground',
              )}
            >
              <span className="flex items-center gap-3">
                <Icon className="h-4 w-4" />
                {l.label}
              </span>
              {showBadge && (
                <span
                  className={cn(
                    'inline-flex min-w-[1.25rem] items-center justify-center rounded-full px-1.5 text-[10px] font-semibold',
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
      <div className="space-y-0.5 p-3">
        <ThemeToggle />
        <button
          type="button"
          onClick={() => signOut({ callbackUrl: '/login' })}
          className="flex w-full items-center gap-3 rounded-md px-3 py-2 text-sm text-sidebar-foreground/70 transition-colors hover:bg-sidebar-accent hover:text-sidebar-accent-foreground"
        >
          <LogOut className="h-4 w-4" />
          Sign out
        </button>
      </div>
    </aside>
  )
}
