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
}

export const NAV_LINKS: ReadonlyArray<NavLink> = [
  { href: '/', label: 'Dashboard', icon: LayoutDashboard },
  { href: '/review', label: 'Review', icon: Inbox, badgeKey: 'review' },
  { href: '/transactions', label: 'Transactions', icon: ArrowLeftRight },
  { href: '/accounts', label: 'Accounts', icon: Wallet },
  { href: '/categories', label: 'Categories', icon: Tags },
  { href: '/reflect', label: 'Reflect', icon: LineChart },
  { href: '/tools', label: 'Tools', icon: Calculator },
  { href: '/settings', label: 'Settings', icon: Settings },
]

export interface NavBadges {
  review?: number
}

export function isLinkActive(linkHref: string, pathname: string): boolean {
  if (linkHref === '/') return pathname === '/'
  return pathname === linkHref || pathname.startsWith(`${linkHref}/`)
}
