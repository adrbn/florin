import {
  ArrowLeftRight,
  BarChart3,
  Calculator,
  CalendarDays,
  Inbox,
  LayoutDashboard,
  LayoutGrid,
  LineChart,
  type LucideIcon,
  PiggyBank,
  Repeat,
  Settings,
  Tags,
  TrendingUp,
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
  /**
   * Optional child links — rendered inline under the parent in the desktop
   * sidebar when the parent is active. Lets us group deep-dive subpages
   * (e.g. Reflect → Trends / Flows / Heatmap) without cluttering the main
   * rail.
   */
  children?: ReadonlyArray<NavLink>
}

export const NAV_LINKS: ReadonlyArray<NavLink> = [
  { href: '/review', label: 'Review', labelKey: 'nav.review', icon: Inbox, badgeKey: 'review', hideWhenEmpty: true },
  { href: '/', label: 'Dashboard', labelKey: 'nav.dashboard', icon: LayoutDashboard },
  { href: '/plan', label: 'Plan', labelKey: 'nav.plan', icon: PiggyBank },
  { href: '/accounts', label: 'Accounts', labelKey: 'nav.accounts', icon: Wallet },
  { href: '/transactions', label: 'Transactions', labelKey: 'nav.transactions', icon: ArrowLeftRight },
  {
    href: '/reflect',
    label: 'Reflect',
    labelKey: 'nav.reflect',
    icon: LineChart,
    children: [
      { href: '/reflect', label: 'Overview', labelKey: 'nav.reflect.overview', icon: LayoutGrid },
      { href: '/reflect/trends', label: 'Trends', labelKey: 'nav.reflect.trends', icon: TrendingUp },
      { href: '/reflect/flows', label: 'Flows', labelKey: 'nav.reflect.flows', icon: BarChart3 },
      { href: '/reflect/heatmap', label: 'Heatmap', labelKey: 'nav.reflect.heatmap', icon: CalendarDays },
      { href: '/reflect/subscriptions', label: 'Subscriptions', labelKey: 'nav.reflect.subscriptions', icon: Repeat },
    ],
  },
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
 * Exact-match variant used by sub-nav children. The Overview child shares
 * the parent's href (`/reflect`), so we can't use the prefix-match version —
 * it would light up Overview on every /reflect/* page.
 */
export function isExactLinkActive(linkHref: string, pathname: string): boolean {
  return pathname === linkHref
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
