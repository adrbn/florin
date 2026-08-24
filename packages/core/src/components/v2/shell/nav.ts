import { ArrowLeftRight, LayoutDashboard, LineChart, Wallet, type LucideIcon } from 'lucide-react'

/** Where the v2 surface is mounted. Both apps use the same prefix. */
export const V2_BASE = '/m'

export interface V2Tab {
  href: string
  labelKey: string
  fallback: string
  icon: LucideIcon
  /** Sub-paths that should still light this tab up. */
  match: (path: string) => boolean
}

function rel(path: string): string {
  return path === V2_BASE ? '/' : path.slice(V2_BASE.length) || '/'
}

/**
 * Five destinations, chosen to cover the daily loop. Everything else — Plan,
 * Review, Categories, Tools, Settings — lives behind the header avatar, which
 * is how a 15-screen app fits a phone without burying one you use every day.
 */
export const V2_TABS: ReadonlyArray<V2Tab> = [
  {
    href: V2_BASE,
    labelKey: 'v2.nav.overview',
    fallback: 'Overview',
    icon: LayoutDashboard,
    match: (p) => rel(p) === '/',
  },
  {
    href: `${V2_BASE}/accounts`,
    labelKey: 'v2.nav.accounts',
    fallback: 'Accounts',
    icon: Wallet,
    match: (p) => rel(p).startsWith('/accounts'),
  },
  {
    href: `${V2_BASE}/transactions`,
    labelKey: 'v2.nav.activity',
    fallback: 'Activity',
    icon: ArrowLeftRight,
    match: (p) => rel(p).startsWith('/transactions'),
  },
  {
    href: `${V2_BASE}/reflect`,
    labelKey: 'v2.nav.analysis',
    fallback: 'Analysis',
    icon: LineChart,
    match: (p) => rel(p).startsWith('/reflect'),
  },
]
