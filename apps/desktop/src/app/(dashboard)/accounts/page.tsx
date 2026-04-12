import Link from 'next/link'
import { AccountsGroupedList } from '@florin/core/components/accounts/accounts-grouped-list'
import { AddAccountCard } from '@florin/core/components/accounts/add-account-card'
import { buttonVariants } from '@florin/core/components/ui/button'
import { queries, db } from '@/db/client'
import { getLoanLiabilities } from '@florin/db-sqlite'
import { reorderAccounts, createAccount, updateAccount } from '@/server/actions/accounts'

interface AccountsPageProps {
  searchParams: Promise<{
    show_archived?: '1'
  }>
}

export default async function AccountsPage({ searchParams }: AccountsPageProps) {
  const params = await searchParams
  const showArchived = params.show_archived === '1'
  const rawAccounts = await queries.listAccounts({ includeArchived: showArchived })

  const liabilityMap = await getLoanLiabilities(db, rawAccounts)
  const accounts = rawAccounts.map((a) => {
    if (a.kind !== 'loan') return a
    const liability = liabilityMap.get(a.id)
    if (!liability) return a
    return { ...a, currentBalance: (-liability.remainingDebt).toFixed(2) }
  })

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">Accounts</h1>
          <p className="text-xs text-muted-foreground">Bank accounts, cash, brokers, and loans</p>
        </div>
        <div className="flex items-center gap-2">
          <Link
            href={showArchived ? ('/accounts' as never) : ('/accounts?show_archived=1' as never)}
            className={buttonVariants({ variant: 'ghost', size: 'sm' })}
          >
            {showArchived ? 'Hide archived' : 'Show archived'}
          </Link>
        </div>
      </div>

      <div className="space-y-3">
        <AccountsGroupedList accounts={accounts} onReorderAccounts={reorderAccounts} />
        <AddAccountCard onCreateAccount={createAccount} onUpdateAccount={updateAccount} />
      </div>
    </div>
  )
}
