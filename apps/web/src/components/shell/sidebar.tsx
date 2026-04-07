'use client'

import { ArrowLeftRight, LayoutDashboard, LogOut, Settings, Tags, Wallet } from 'lucide-react'
import Link from 'next/link'
import { usePathname } from 'next/navigation'
import { signOut } from 'next-auth/react'
import { cn } from '@/lib/utils'

const links = [
  { href: '/', label: 'Dashboard', icon: LayoutDashboard },
  { href: '/transactions', label: 'Transactions', icon: ArrowLeftRight },
  { href: '/accounts', label: 'Accounts', icon: Wallet },
  { href: '/categories', label: 'Categories', icon: Tags },
  { href: '/settings', label: 'Settings', icon: Settings },
] as const

export function Sidebar() {
  const pathname = usePathname()
  return (
    <aside className="w-64 border-r bg-muted/30 flex flex-col">
      <div className="p-6">
        <h2 className="text-2xl font-bold tracking-tight">Florin</h2>
      </div>
      <nav className="flex-1 px-3 space-y-1">
        {links.map((l) => {
          const Icon = l.icon
          const active = pathname === l.href
          return (
            <Link
              key={l.href}
              href={l.href}
              className={cn(
                'flex items-center gap-3 px-3 py-2 rounded-md text-sm transition-colors',
                active
                  ? 'bg-primary text-primary-foreground'
                  : 'text-muted-foreground hover:bg-muted hover:text-foreground',
              )}
            >
              <Icon className="h-4 w-4" />
              {l.label}
            </Link>
          )
        })}
      </nav>
      <div className="p-3">
        <button
          type="button"
          onClick={() => signOut({ callbackUrl: '/login' })}
          className="flex items-center gap-3 px-3 py-2 rounded-md text-sm w-full text-muted-foreground hover:bg-muted hover:text-foreground transition-colors"
        >
          <LogOut className="h-4 w-4" />
          Sign out
        </button>
      </div>
    </aside>
  )
}
