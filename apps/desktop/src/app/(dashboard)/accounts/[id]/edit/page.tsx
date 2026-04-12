import Link from 'next/link'
import { notFound } from 'next/navigation'
import { AccountForm, type AccountFormInitial } from '@florin/core/components/accounts/account-form'
import { Card, CardContent, CardHeader, CardTitle } from '@florin/core/components/ui/card'
import { getAccountById, createAccount, updateAccount } from '@/server/actions/accounts'

interface AccountEditPageProps {
  params: Promise<{ id: string }>
}

export default async function AccountEditPage({ params }: AccountEditPageProps) {
  const { id } = await params
  const account = await getAccountById(id)
  if (!account) notFound()

  const initial: AccountFormInitial = {
    id: account.id,
    name: account.name,
    kind: account.kind,
    institution: account.institution,
    currentBalance: account.currentBalance,
    displayIcon: account.displayIcon,
    displayColor: account.displayColor,
    isIncludedInNetWorth: account.isIncludedInNetWorth,
  }

  return (
    <div className="mx-auto max-w-xl space-y-6">
      <Link
        href={`/accounts/${account.id}`}
        className="text-xs uppercase tracking-wide text-muted-foreground hover:text-foreground"
      >
        ← {account.name}
      </Link>
      <Card>
        <CardHeader>
          <CardTitle>Edit account</CardTitle>
        </CardHeader>
        <CardContent>
          <AccountForm
            initial={initial}
            onCreateAccount={createAccount}
            onUpdateAccount={updateAccount}
          />
        </CardContent>
      </Card>
    </div>
  )
}
