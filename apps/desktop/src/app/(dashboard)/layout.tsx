import { MobileTopBar } from '@florin/core/components/shell/mobile-topbar'
import { Sidebar } from '@florin/core/components/shell/sidebar'
import { countNeedsReview } from '@/server/actions/transactions'

// Every page under (dashboard) reads live database state, so none of them
// should be statically prerendered at build time. Pin the whole group to
// dynamic to keep the rendered output in sync with the DB on every request.
export const dynamic = 'force-dynamic'

export default async function DashboardLayout({ children }: { children: React.ReactNode }) {
  // Compute the review badge once per render so both the sidebar and the
  // mobile top bar can show a live count without each child page having to
  // plumb it through manually.
  const reviewCount = await countNeedsReview()
  const badges = { review: reviewCount }

  // Layout direction flips at `md`: mobile stacks the top bar above a
  // scrollable main area, desktop places the sidebar side-by-side with
  // a scrollable main. Using `h-dvh` instead of `h-screen` handles iOS
  // Safari's shrinking address bar so the content always fits the real
  // visible viewport.
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
