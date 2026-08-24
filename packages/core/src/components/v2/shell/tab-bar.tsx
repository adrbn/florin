'use client'

import { Plus } from 'lucide-react'
import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { useV2T } from '../i18n/context'
import { useScrollChrome } from '../lib/use-scroll'
import { cn } from '../../../lib/utils'
import { V2_TABS } from './nav'

/**
 * Floating glass tab bar. Four destinations with the add action in the middle
 * — the arrangement every neobank converged on, because the thumb rests there.
 *
 * It slides away on scroll-down and returns on scroll-up, which buys back 62px
 * of a 390px-wide screen exactly when the user is reading a long list.
 */
export function V2TabBar({ onAdd }: { onAdd: () => void }) {
  const pathname = usePathname() ?? '/'
  const { hidden } = useScrollChrome()
  const t = useV2T()

  const left = V2_TABS.slice(0, 2)
  const right = V2_TABS.slice(2)

  return (
    <nav
      aria-label={t('v2.a11y.primaryNav', 'Primary navigation')}
      className="v2-tabbar"
      data-hidden={hidden || undefined}
    >
      {left.map((tab) => (
        <TabLink key={tab.href} tab={tab} pathname={pathname} />
      ))}

      <button
        type="button"
        onClick={onAdd}
        aria-label={t('v2.nav.add', 'Add')}
        className="v2-tab-fab"
      >
        <Plus className="h-5 w-5" strokeWidth={2.4} />
      </button>

      {right.map((tab) => (
        <TabLink key={tab.href} tab={tab} pathname={pathname} />
      ))}
    </nav>
  )
}

function TabLink({
  tab,
  pathname,
}: {
  tab: (typeof V2_TABS)[number]
  pathname: string
}) {
  const t = useV2T()
  const Icon = tab.icon
  const active = tab.match(pathname)
  return (
    <Link
      href={tab.href as never}
      aria-current={active ? 'page' : undefined}
      data-active={active}
      className="v2-tab"
    >
      <Icon
        className={cn('h-[19px] w-[19px] transition-transform', active && 'scale-105')}
        strokeWidth={active ? 2.2 : 1.7}
      />
      <span>{t(tab.labelKey, tab.fallback)}</span>
    </Link>
  )
}
