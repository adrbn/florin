import { count } from 'drizzle-orm'
import Link from 'next/link'
import { db } from '@/db/client'
import { accounts } from '@/db/schema'

/**
 * Lightweight nudge that appears at the top of the dashboard until the user
 * has at least one account. Server-rendered so there's zero client JS.
 *
 * If the install is fresh (no accounts at all) we show a hard call to
 * action; otherwise we render nothing.
 */
export async function OnboardingBanner() {
  const [row] = await db.select({ value: count() }).from(accounts)
  const total = Number(row?.value ?? 0)
  if (total > 0) return null

  return (
    <div className="rounded-lg border border-primary/30 bg-primary/5 px-4 py-3 text-sm shadow-sm">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <p className="font-semibold text-foreground">👋 Welcome to Florin</p>
          <p className="text-xs text-muted-foreground">
            Set up your first accounts and categories — takes about a minute.
          </p>
        </div>
        <Link
          href="/onboarding"
          className="inline-flex items-center rounded-md bg-primary px-3 py-1.5 text-xs font-medium text-primary-foreground shadow-sm transition-colors hover:bg-primary/90"
        >
          Start onboarding →
        </Link>
      </div>
    </div>
  )
}
