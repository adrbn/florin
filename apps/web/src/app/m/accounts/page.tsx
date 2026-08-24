import { AccountsScreen } from '@florin/core/components/v2/screens/accounts'
import { mapAccount } from '@florin/core/components/v2/lib/map'
import { getLoanLiabilities } from '@florin/db-pg'
import { db, queries } from '@/db/client'
import { isEnableBankingConfigured } from '@/server/banking/enable-banking'

export const dynamic = 'force-dynamic'

export default async function V2Accounts() {
  const [accounts, netWorth] = await Promise.all([
    queries.listAccounts(),
    queries.getNetWorth(),
  ])
  const liabilities = await getLoanLiabilities(db, accounts)
  return (
    <AccountsScreen
      accounts={accounts.map((a) => mapAccount(a, liabilities.get(a.id)?.remainingDebt))}
      net={netWorth.net}
      bankSyncConfigured={isEnableBankingConfigured()}
    />
  )
}
