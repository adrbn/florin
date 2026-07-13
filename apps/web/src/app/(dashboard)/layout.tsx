import { headers } from 'next/headers'
import { redirect } from 'next/navigation'
import { MobileTopBar } from '@florin/core/components/shell/mobile-topbar'
import { Sidebar } from '@florin/core/components/shell/sidebar'
import { KeyboardShortcuts } from '@florin/core/components/shortcuts/keyboard-shortcuts'
import { mutations, queries } from '@/db/client'
import { countNeedsReview } from '@/server/actions/transactions'
import { ensureAutoSyncScheduler } from '@/server/banking/scheduler'
import { getUpdateStatus, UPDATE_COMMAND } from '@/server/updates/github'
import pkg from '../../../package.json'

// Every page under (dashboard) reads live database state, so none of them
// should be statically prerendered at build time. Pin the whole group to
// dynamic to keep the rendered output in sync with the DB on every request.
export const dynamic = 'force-dynamic'

export default async function DashboardLayout({ children }: { children: React.ReactNode }) {
  // Kick off the background bank-sync scheduler on first request. After the
  // first call this is a no-op thanks to a module-level singleton flag, so
  // it's cheap to call on every navigation.
  ensureAutoSyncScheduler()

  // Top up scheduled (forecast) transactions from recurring rules. Idempotent
  // and cheap (a no-op when there are no rules); fire-and-forget so it never
  // blocks render.
  void mutations.materializeScheduledTransactions().catch(() => {})

  // Refresh security price quotes. No-op when the price provider is disabled
  // (the default); otherwise fetches fresh quotes and recomputes portfolio
  // market values. Fire-and-forget so a slow/offline provider never blocks
  // render. Imported lazily so the pricing fetch path isn't pulled into the
  // layout's hot module graph.
  void import('@/server/pricing/refresh')
    .then((m) => m.refreshPriceQuotes())
    .catch(() => {})

  // On first launch, when there are no accounts, send the user through the
  // onboarding wizard (mirrors the desktop layout). We skip the redirect when
  // already on /onboarding to avoid an infinite loop — that page lives in this
  // same route group, so the layout wraps it too. The pathname comes from the
  // `x-pathname` header set by middleware.
  const [headersList, reviewCount, accountList, update] = await Promise.all([
    headers(),
    countNeedsReview(),
    queries.listAccounts(),
    getUpdateStatus(pkg.version),
  ])

  const pathname = headersList.get('x-pathname') ?? ''
  const isOnboarding = pathname.startsWith('/onboarding')

  if (!isOnboarding && accountList.length === 0) {
    redirect('/onboarding')
  }

  const badges = { review: reviewCount }

  // Layout direction flips at `md`: mobile stacks the top bar above a
  // scrollable main area, desktop places the sidebar side-by-side with
  // a scrollable main. Using `h-dvh` instead of `h-screen` handles iOS
  // Safari's shrinking address bar so the content always fits the real
  // visible viewport — no more swipe-right / swipe-down to reveal the
  // last 16px of the page.
  return (
    <div className="flex h-dvh w-full flex-col overflow-hidden md:flex-row">
      <Sidebar
        badges={badges}
        update={update ? { ...update, command: UPDATE_COMMAND } : null}
      />
      <MobileTopBar badges={badges} />
      <main className="min-w-0 flex-1 overflow-y-auto overflow-x-hidden px-4 pt-4 pb-[calc(1rem_+_env(safe-area-inset-bottom))] md:p-6 lg:p-8">
        {children}
      </main>
      <KeyboardShortcuts />
    </div>
  )
}
