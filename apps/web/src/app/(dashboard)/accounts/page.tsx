import Link from 'next/link'
import { AccountsGroupedList } from '@/components/accounts/accounts-grouped-list'
import { AddAccountCard } from '@/components/accounts/add-account-card'
import { BankConnectionList } from '@/components/accounts/bank-connection-list'
import { buttonVariants } from '@/components/ui/button'
import { listAccounts } from '@/server/actions/accounts'
import { isEnableBankingConfigured } from '@/server/banking/enable-banking'
import { getLoanLiabilities } from '@/server/queries/loan-liabilities'

interface AccountsPageProps {
  searchParams: Promise<{
    bank_link?: 'success' | 'cancelled' | 'error'
    reason?: string
    connection?: string
    show_archived?: '1'
  }>
}

function BankLinkBanner({
  status,
  reason,
}: {
  status: 'success' | 'cancelled' | 'error'
  reason?: string
}) {
  if (status === 'success') {
    return (
      <div className="rounded-md border border-emerald-500/40 bg-emerald-500/10 px-4 py-3 text-sm text-emerald-900 dark:text-emerald-100">
        ✅ Bank linked. Initial sync complete — your accounts and transactions are now live below.
      </div>
    )
  }
  if (status === 'cancelled') {
    return (
      <div className="rounded-md border border-amber-500/40 bg-amber-500/10 px-4 py-3 text-sm text-amber-900 dark:text-amber-100">
        ⚠️ Bank linking cancelled{reason ? `: ${decodeURIComponent(reason)}` : '.'}
      </div>
    )
  }
  return (
    <div className="rounded-md border border-destructive/40 bg-destructive/10 px-4 py-3 text-sm text-destructive">
      ❌ Bank linking failed{reason ? `: ${decodeURIComponent(reason)}` : '.'} You can retry from
      the Connect bank button below.
    </div>
  )
}

export default async function AccountsPage({ searchParams }: AccountsPageProps) {
  const params = await searchParams
  const showArchived = params.show_archived === '1'
  const rawAccounts = await listAccounts({ includeArchived: showArchived })
  const bankingEnabled = isEnableBankingConfigured()

  // Replace loan currentBalance with the amortization-derived liability
  // shown as a negative number, so the Loan bucket in the grouped list
  // reflects the real "capital restant dû" instead of the running sum of
  // payment mirrors (which was flipped positive and misled the user into
  // thinking the loan was an asset). Non-loan accounts pass through
  // unchanged.
  const liabilityMap = await getLoanLiabilities(rawAccounts)
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
          {bankingEnabled && (
            <Link
              href="/accounts/connect"
              className={buttonVariants({ variant: 'default', size: 'sm' })}
            >
              + Connect bank
            </Link>
          )}
        </div>
      </div>

      {params.bank_link && <BankLinkBanner status={params.bank_link} reason={params.reason} />}

      <div className="space-y-3">
        <AccountsGroupedList accounts={accounts} />
        <AddAccountCard />
      </div>

      {/* Linked banks live below the accounts grid — the grid is the thing
       *  the user actually scans every time, and bank-connection management
       *  is a once-a-year task. Putting it up top was dominant visual weight
       *  for a low-frequency control. */}
      {bankingEnabled && <BankConnectionList />}
    </div>
  )
}
