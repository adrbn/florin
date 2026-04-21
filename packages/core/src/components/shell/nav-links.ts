import {
  ArrowLeftRight,
  Calculator,
  Inbox,
  LayoutDashboard,
  LineChart,
  type LucideIcon,
  PiggyBank,
  Settings,
  Tags,
  Wallet,
} from 'lucide-react'

// Shared nav list — consumed by both the desktop sidebar and the mobile top
// bar so the set of destinations never drifts between surfaces.
export interface NavLink {
  href: string
  label: string
  /**
   * i18n key for the nav label. Paired with `label` as the English fallback
   * so existing server-side rendering keeps working if the provider is
   * missing or the key isn't in the dictionary yet.
   */
  labelKey: string
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
  { href: '/review', label: 'Review', labelKey: 'nav.review', icon: Inbox, badgeKey: 'review', hideWhenEmpty: true },
  { href: '/', label: 'Dashboard', labelKey: 'nav.dashboard', icon: LayoutDashboard },
  { href: '/plan', label: 'Plan', labelKey: 'nav.plan', icon: PiggyBank },
  { href: '/accounts', label: 'Accounts', labelKey: 'nav.accounts', icon: Wallet },
  { href: '/transactions', label: 'Transactions', labelKey: 'nav.transactions', icon: ArrowLeftRight },
  { href: '/reflect', label: 'Reflect', labelKey: 'nav.reflect', icon: LineChart },
  { href: '/tools', label: 'Tools', labelKey: 'nav.tools', icon: Calculator },
  { href: '/categories', label: 'Categories', labelKey: 'nav.categories', icon: Tags },
  { href: '/settings', label: 'Settings', labelKey: 'nav.settings', icon: Settings },
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
