import { eq, asc } from 'drizzle-orm'
import { headers } from 'next/headers'
import { redirect } from 'next/navigation'
import { DesktopSidebar } from '@/components/desktop-sidebar'
import { KeyboardShortcuts } from '@florin/core/components/shortcuts/keyboard-shortcuts'
import { QuickAddFab } from '@/components/quick-add-fab'
import { countNeedsReview } from '@/server/actions/transactions'
import { addTransaction } from '@/server/actions/transactions'
import { queries } from '@/db/client'
import { db } from '@/db/client'
import { categories, categoryGroups } from '@/db/schema'

// Every page under (dashboard) reads live database state, so none of them
// should be statically prerendered at build time. Pin the whole group to
// dynamic to keep the rendered output in sync with the DB on every request.
export const dynamic = 'force-dynamic'

export default async function DashboardLayout({ children }: { children: React.ReactNode }) {
  // On first launch, when there are no accounts, send the user through the
  // onboarding wizard. We skip the redirect when the user is already on
  // /onboarding to avoid an infinite redirect loop (the layout wraps that page
  // too since it lives in the same route group).
  const [headersList, reviewCount, accountList, categoryList] = await Promise.all([
    headers(),
    countNeedsReview(),
    queries.listAccounts(),
    db
      .select({
        id: categories.id,
        name: categories.name,
        emoji: categories.emoji,
        groupName: categoryGroups.name,
      })
      .from(categories)
      .innerJoin(categoryGroups, eq(categories.groupId, categoryGroups.id))
      .orderBy(asc(categoryGroups.name), asc(categories.name)),
  ])

  const pathname = headersList.get('x-pathname') ?? headersList.get('x-invoke-path') ?? ''
  const isOnboarding = pathname.startsWith('/onboarding')

  if (!isOnboarding && accountList.length === 0) {
    redirect('/onboarding')
  }

  const badges = { review: reviewCount }
  const fabAccounts = accountList.map((a) => ({ id: a.id, name: a.name }))

  // Layout direction flips at `md`: mobile stacks the top bar above a
  // scrollable main area, desktop places the sidebar side-by-side with
  // a scrollable main. Using `h-dvh` instead of `h-screen` handles iOS
  // Safari's shrinking address bar so the content always fits the real
  // visible viewport.
  return (
    <div className="flex h-dvh w-full flex-col overflow-hidden md:flex-row">
      <DesktopSidebar badges={badges} />
      {/* Draggable title bar region across the main content area — sits above
          content but only captures drag, clicks pass through to buttons below. */}
      <div className="pointer-events-auto absolute left-60 right-0 top-0 z-40 hidden h-8 md:block" style={{ WebkitAppRegion: 'drag' } as React.CSSProperties} />
      <main className="min-w-0 flex-1 overflow-y-auto overflow-x-hidden p-4 pt-8 md:p-6 md:pt-8 lg:p-8 lg:pt-8">
        {children}
      </main>
      <QuickAddFab
        accounts={fabAccounts}
        categories={categoryList}
        onAddTransaction={addTransaction}
      />
      <KeyboardShortcuts />
    </div>
  )
}
