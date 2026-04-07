import { AccountForm } from '@/components/accounts/account-form'
import { Badge } from '@/components/ui/badge'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { formatCurrency } from '@/lib/format/currency'
import { listAccounts } from '@/server/actions/accounts'

export default async function AccountsPage() {
  const accounts = await listAccounts()

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Accounts</h1>
        <p className="text-muted-foreground">Manage your bank accounts, cash, and brokers.</p>
      </div>

      <div className="grid gap-6 lg:grid-cols-3">
        <div className="lg:col-span-2 space-y-4">
          {accounts.length === 0 ? (
            <Card>
              <CardContent className="py-12 text-center text-muted-foreground">
                No accounts yet. Create one →
              </CardContent>
            </Card>
          ) : (
            <div className="grid gap-4 sm:grid-cols-2">
              {accounts.map((account) => (
                <Card key={account.id}>
                  <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                    <div className="flex items-center gap-2">
                      {account.displayIcon && (
                        <span className="text-xl" aria-hidden>
                          {account.displayIcon}
                        </span>
                      )}
                      <CardTitle className="text-base">{account.name}</CardTitle>
                    </div>
                    <Badge variant="secondary">{account.kind}</Badge>
                  </CardHeader>
                  <CardContent className="space-y-1">
                    <p className="text-2xl font-bold">{formatCurrency(account.currentBalance)}</p>
                    {account.institution && (
                      <p className="text-xs text-muted-foreground">{account.institution}</p>
                    )}
                  </CardContent>
                </Card>
              ))}
            </div>
          )}
        </div>

        <Card>
          <CardHeader>
            <CardTitle>New account</CardTitle>
          </CardHeader>
          <CardContent>
            <AccountForm />
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
