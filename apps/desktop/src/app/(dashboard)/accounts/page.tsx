import Link from 'next/link'
import { AccountsGroupedList } from '@florin/core/components/accounts/accounts-grouped-list'
import { AddAccountCard } from '@florin/core/components/accounts/add-account-card'
import { BankConnectionList } from '@florin/core/components/accounts/bank-connection-list'
import { buttonVariants } from '@florin/core/components/ui/button'
import { queries, db } from '@/db/client'
import { getServerT } from '@/lib/locale'
import { getLoanLiabilities } from '@florin/db-sqlite'
import { reorderAccounts, createAccount, updateAccount } from '@/server/actions/accounts'
import {
  isEnableBankingConfigured,
  syncBankConnection,
  resetBankConnectionSync,
  revokeBankConnection,
} from '@/server/actions/banking'

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
        Bank linked. Initial sync complete — your accounts and transactions are now live below.
      </div>
    )
  }
  if (status === 'cancelled') {
    return (
      <div className="rounded-md border border-amber-500/40 bg-amber-500/10 px-4 py-3 text-sm text-amber-900 dark:text-amber-100">
        Bank linking cancelled{reason ? `: ${decodeURIComponent(reason)}` : '.'}
      </div>
    )
  }
  return (
    <div className="rounded-md border border-destructive/40 bg-destructive/10 px-4 py-3 text-sm text-destructive">
      Bank linking failed{reason ? `: ${decodeURIComponent(reason)}` : '.'} You can retry from
      the Connect bank button below.
    </div>
  )
}

export default async function AccountsPage({ searchParams }: AccountsPageProps) {
  const t = await getServerT()
  const params = await searchParams
  const showArchived = params.show_archived === '1'
  const rawAccounts = await queries.listAccounts({ includeArchived: showArchived })
  const bankingEnabled = await isEnableBankingConfigured()

  const liabilityMap = await getLoanLiabilities(db, rawAccounts)
  const accounts = rawAccounts.map((a) => {
    if (a.kind !== 'loan') return a
    const liability = liabilityMap.get(a.id)
    if (!liability) return a
    return { ...a, currentBalance: (-liability.remainingDebt).toFixed(2) }
  })

  const bankConnectionRows = bankingEnabled ? await queries.listBankConnections() : []

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">{t('accounts.title', 'Accounts')}</h1>
          <p className="text-xs text-muted-foreground">
            {t('accounts.subtitle', 'Bank accounts, cash, brokers, and loans')}
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Link
            href={showArchived ? ('/accounts' as never) : ('/accounts?show_archived=1' as never)}
            className={buttonVariants({ variant: 'ghost', size: 'sm' })}
          >
            {showArchived
              ? t('accounts.hideArchived', 'Hide archived')
              : t('accounts.showArchived', 'Show archived')}
          </Link>
          {bankingEnabled && (
            <Link
              href={'/accounts/connect' as never}
              className={buttonVariants({ variant: 'default', size: 'sm' })}
            >
              + {t('accounts.connectBank', 'Connect bank')}
            </Link>
          )}
        </div>
      </div>

      {params.bank_link && <BankLinkBanner status={params.bank_link} reason={params.reason} />}

      <div className="space-y-3">
        <AccountsGroupedList accounts={accounts} onReorderAccounts={reorderAccounts} />
        <AddAccountCard onCreateAccount={createAccount} onUpdateAccount={updateAccount} />
      </div>

      {bankingEnabled && (
        <BankConnectionList
          rows={bankConnectionRows}
          onSyncBankConnection={syncBankConnection}
          onResetBankConnectionSync={resetBankConnectionSync}
          onRevokeBankConnection={revokeBankConnection}
        />
      )}
    </div>
  )
}
