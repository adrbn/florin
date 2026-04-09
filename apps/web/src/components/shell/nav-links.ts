import {
  ArrowLeftRight,
  Calculator,
  Inbox,
  LayoutDashboard,
  LineChart,
  type LucideIcon,
  Settings,
  Tags,
  Wallet,
} from 'lucide-react'

// Shared nav list — consumed by both the desktop sidebar and the mobile top
// bar so the set of destinations never drifts between surfaces.
export interface NavLink {
  href: string
  label: string
  icon: LucideIcon
  badgeKey?: 'review'
  /**
   * If true, the link is hidden entirely when its badge is absent or zero.
   * Used for Review — there's no point taking up a nav slot when the queue
   * is empty.
   */
  hideWhenEmpty?: boolean
}

export const NAV_LINKS: ReadonlyArray<NavLink> = [
  { href: '/', label: 'Dashboard', icon: LayoutDashboard },
  { href: '/review', label: 'Review', icon: Inbox, badgeKey: 'review', hideWhenEmpty: true },
  { href: '/accounts', label: 'Accounts', icon: Wallet },
  { href: '/transactions', label: 'Transactions', icon: ArrowLeftRight },
  { href: '/reflect', label: 'Reflect', icon: LineChart },
  { href: '/tools', label: 'Tools', icon: Calculator },
  { href: '/categories', label: 'Categories', icon: Tags },
  { href: '/settings', label: 'Settings', icon: Settings },
]

export interface NavBadges {
  review?: number
}

export function isLinkActive(linkHref: string, pathname: string): boolean {
  if (linkHref === '/') return pathname === '/'
  return pathname === linkHref || pathname.startsWith(`${linkHref}/`)
}

/**
 * Filter the nav list down to links that should currently render, honouring
 * `hideWhenEmpty` against the live badge counts. Single source of truth so
 * the desktop sidebar and mobile top bar can't drift.
 */
export function visibleNavLinks(badges?: NavBadges): ReadonlyArray<NavLink> {
  return NAV_LINKS.filter((l) => {
    if (!l.hideWhenEmpty) return true
    const badgeValue = l.badgeKey ? badges?.[l.badgeKey] : undefined
    return typeof badgeValue === 'number' && badgeValue > 0
  })
}
