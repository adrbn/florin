import { asc } from 'drizzle-orm'
import { AddTransactionModal } from '@/components/transactions/add-transaction-modal'
import { Card } from '@/components/ui/card'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { db } from '@/db/client'
import { categories } from '@/db/schema'
import { formatCurrencySigned } from '@/lib/format/currency'
import { listAccounts } from '@/server/actions/accounts'
import { listTransactions } from '@/server/actions/transactions'

const dateFormatter = new Intl.DateTimeFormat('fr-FR', {
  day: '2-digit',
  month: '2-digit',
  year: 'numeric',
})

export default async function TransactionsPage() {
  const [txns, accountsList, categoryList] = await Promise.all([
    listTransactions({ limit: 200 }),
    listAccounts(),
    db.select().from(categories).orderBy(asc(categories.name)),
  ])

  const accountOptions = accountsList.map((a) => ({ id: a.id, name: a.name }))
  const categoryOptions = categoryList.map((c) => ({
    id: c.id,
    name: c.name,
    emoji: c.emoji,
  }))

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Transactions</h1>
          <p className="text-muted-foreground">Recent activity across all accounts.</p>
        </div>
        <AddTransactionModal accounts={accountOptions} categories={categoryOptions} />
      </div>

      <Card>
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead className="w-28">Date</TableHead>
              <TableHead>Payee</TableHead>
              <TableHead>Account</TableHead>
              <TableHead>Category</TableHead>
              <TableHead className="text-right">Amount</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {txns.length === 0 ? (
              <TableRow>
                <TableCell colSpan={5} className="py-12 text-center text-muted-foreground">
                  No transactions yet. Click "Add transaction" to get started.
                </TableCell>
              </TableRow>
            ) : (
              txns.map((t) => {
                const amount = Number(t.amount)
                const isNegative = amount < 0
                return (
                  <TableRow key={t.id}>
                    <TableCell className="font-mono text-xs text-muted-foreground">
                      {dateFormatter.format(t.occurredAt)}
                    </TableCell>
                    <TableCell className="font-medium">{t.payee}</TableCell>
                    <TableCell className="text-muted-foreground">
                      {t.account?.name ?? '—'}
                    </TableCell>
                    <TableCell className="text-muted-foreground">
                      {t.category ? (
                        <span>
                          {t.category.emoji ? `${t.category.emoji} ` : ''}
                          {t.category.name}
                        </span>
                      ) : (
                        '—'
                      )}
                    </TableCell>
                    <TableCell
                      className={`text-right font-mono tabular-nums ${
                        isNegative ? 'text-destructive' : 'text-emerald-600'
                      }`}
                    >
                      {formatCurrencySigned(amount)}
                    </TableCell>
                  </TableRow>
                )
              })
            )}
          </TableBody>
        </Table>
      </Card>
    </div>
  )
}
