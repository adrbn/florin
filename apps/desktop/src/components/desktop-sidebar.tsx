'use client'

import { Info } from 'lucide-react'
import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { ThemeToggle } from '@florin/core/components/theme/theme-toggle'
import { LocaleSwitcher } from '@florin/core/components/shell/locale-switcher'
import { cn } from '@florin/core/lib/utils'
import { useT } from '@florin/core/i18n/context'
import { isLinkActive, type NavBadges, visibleNavLinks } from '@florin/core/components/shell/nav-links'

interface DesktopSidebarProps {
  badges?: NavBadges
}

export function DesktopSidebar({ badges }: DesktopSidebarProps) {
  const pathname = usePathname()
  const t = useT()
  const links = visibleNavLinks(badges)
  return (
    <aside className="hidden w-60 shrink-0 flex-col border-r bg-sidebar text-sidebar-foreground md:flex">
      <div className="flex items-center gap-3 px-6 pb-5 pt-10" style={{ WebkitAppRegion: 'drag' } as React.CSSProperties}>
        <span
          aria-hidden
          className="h-2.5 w-2.5 rounded-full bg-sidebar-primary shadow-[0_0_6px_2px_hsl(var(--sidebar-primary)/0.3)]"
        />
        <h2
          className="text-2xl font-bold leading-none"
          style={{ fontFamily: "'Tuaf', ui-sans-serif, system-ui, sans-serif", letterSpacing: '-0.02em' }}
        >
          Florin
        </h2>
      </div>
      <nav className="flex-1 space-y-0.5 px-3">
        {links.map((l) => {
          const Icon = l.icon
          const active = isLinkActive(l.href, pathname)
          const badgeValue = l.badgeKey ? badges?.[l.badgeKey] : undefined
          const showBadge = typeof badgeValue === 'number' && badgeValue > 0
          const isNotification = l.badgeKey === 'review' && showBadge
          return (
            <Link
              key={l.href}
              href={l.href as never}
              className={cn(
                'flex items-center justify-between gap-3 rounded-md px-3 py-2 text-sm transition-colors',
                active
                  ? 'bg-sidebar-primary text-sidebar-primary-foreground'
                  : isNotification
                  ? 'bg-rose-500/10 text-rose-700 hover:bg-rose-500/20 dark:text-rose-300'
                  : 'text-sidebar-foreground/70 hover:bg-sidebar-accent hover:text-sidebar-accent-foreground',
              )}
            >
              <span className="flex items-center gap-3">
                <Icon className="h-4 w-4" />
                {t(l.labelKey, l.label)}
              </span>
              {showBadge && (
                <span
                  className={cn(
                    'inline-flex min-w-[1.25rem] items-center justify-center rounded-full px-1.5 text-[10px] font-semibold',
                    active
                      ? 'bg-sidebar-primary-foreground/20 text-sidebar-primary-foreground'
                      : isNotification
                      ? 'bg-rose-500/20 text-rose-700 dark:text-rose-300'
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
        <LocaleSwitcher endpoint="/api/settings/locale" />
        <ThemeToggle />
        <Link
          href="/about"
          className={cn(
            'flex w-full items-center gap-3 rounded-md px-3 py-2 text-sm transition-colors',
            pathname === '/about'
              ? 'bg-sidebar-primary text-sidebar-primary-foreground'
              : 'text-sidebar-foreground/70 hover:bg-sidebar-accent hover:text-sidebar-accent-foreground',
          )}
        >
          <Info className="h-4 w-4" />
          {t('nav.about', 'About')}
        </Link>
      </div>
    </aside>
  )
}
