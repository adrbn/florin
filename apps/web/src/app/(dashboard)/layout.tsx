import { MobileTopBar } from '@florin/core/components/shell/mobile-topbar'
import { Sidebar } from '@florin/core/components/shell/sidebar'
import { countNeedsReview } from '@/server/actions/transactions'
import { ensureAutoSyncScheduler } from '@/server/banking/scheduler'

// Every page under (dashboard) reads live database state, so none of them
// should be statically prerendered at build time. Pin the whole group to
// dynamic to keep the rendered output in sync with the DB on every request.
export const dynamic = 'force-dynamic'

export default async function DashboardLayout({ children }: { children: React.ReactNode }) {
  // Kick off the background bank-sync scheduler on first request. After the
  // first call this is a no-op thanks to a module-level singleton flag, so
  // it's cheap to call on every navigation.
  ensureAutoSyncScheduler()

  // Compute the review badge once per render so both the sidebar and the
  // mobile top bar can show a live count without each child page having to
  // plumb it through manually.
  const reviewCount = await countNeedsReview()
  const badges = { review: reviewCount }

  // Layout direction flips at `md`: mobile stacks the top bar above a
  // scrollable main area, desktop places the sidebar side-by-side with
  // a scrollable main. Using `h-dvh` instead of `h-screen` handles iOS
  // Safari's shrinking address bar so the content always fits the real
  // visible viewport — no more swipe-right / swipe-down to reveal the
  // last 16px of the page.
  return (
    <div className="flex h-dvh w-full flex-col overflow-hidden md:flex-row">
      <Sidebar badges={badges} />
      <MobileTopBar badges={badges} />
      <main className="min-w-0 flex-1 overflow-y-auto overflow-x-hidden p-4 md:p-6 lg:p-8">
        {children}
      </main>
    </div>
  )
}
