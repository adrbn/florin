import { asc, eq } from 'drizzle-orm'
import Link from 'next/link'
import { AddTransactionModal } from '@/components/transactions/add-transaction-modal'
import { DeleteTransactionButton } from '@/components/transactions/delete-transaction-button'
import { TransactionCategoryCell } from '@/components/transactions/transaction-category-cell'
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
import { categories, categoryGroups } from '@/db/schema'
import { formatCurrency, formatCurrencySigned } from '@/lib/format/currency'
import { listAccounts } from '@/server/actions/accounts'
import { listTransactions, type TransactionDirection } from '@/server/actions/transactions'

const dateFormatter = new Intl.DateTimeFormat('fr-FR', {
  day: '2-digit',
  month: '2-digit',
  year: 'numeric',
})

const longDateFormatter = new Intl.DateTimeFormat('fr-FR', {
  day: '2-digit',
  month: 'long',
  year: 'numeric',
})

/** Parse a YYYY-MM-DD string into a local-midnight Date, or return null if
 *  the input is missing or malformed. We stay strict on the shape so a
 *  broken querystring can't silently widen the filter window. */
function parseIsoDate(raw: string | undefined): Date | null {
  if (!raw) return null
  if (!/^\d{4}-\d{2}-\d{2}$/.test(raw)) return null
  const [y, m, d] = raw.split('-').map(Number)
  if (!y || !m || !d) return null
  const date = new Date(y, m - 1, d)
  return Number.isNaN(date.getTime()) ? null : date
}

function parseDirection(raw: string | undefined): TransactionDirection {
  if (raw === 'expense' || raw === 'income') return raw
  return 'all'
}

interface TransactionsPageProps {
  searchParams: Promise<{
    from?: string
    to?: string
    direction?: string
    excludeTransfers?: string
  }>
}

export default async function TransactionsPage({ searchParams }: TransactionsPageProps) {
  const sp = await searchParams
  const startDate = parseIsoDate(sp.from)
  const endOfDay = parseIsoDate(sp.to)
  // Honor "to" as inclusive: bump it to the very end of that day so the
  // user sees the last day's transactions, not everything before it.
  const endDate = endOfDay
    ? new Date(endOfDay.getFullYear(), endOfDay.getMonth(), endOfDay.getDate(), 23, 59, 59, 999)
    : null
  const direction = parseDirection(sp.direction)
  const excludeTransfers = sp.excludeTransfers === '1' || sp.excludeTransfers === 'true'
  const hasFilter = Boolean(startDate || endDate || direction !== 'all' || excludeTransfers)

  const [txns, accountsList, categoryList] = await Promise.all([
    listTransactions({
      limit: 500,
      startDate: startDate ?? undefined,
      endDate: endDate ?? undefined,
      direction,
      excludeTransfers,
    }),
    listAccounts(),
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

  const accountOptions = accountsList.map((a) => ({ id: a.id, name: a.name }))
  const categoryOptions = categoryList.map((c) => ({
    id: c.id,
    name: c.name,
    emoji: c.emoji,
    groupName: c.groupName,
  }))

  // When a filter is active we also compute the total so the page doubles
  // as a verification surface — the user can eyeball the headline Burn
  // KPI and the sum here and know they match.
  const filteredTotal = hasFilter
    ? txns.reduce((acc, t) => acc + Math.abs(Number(t.amount)), 0)
    : null

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Transactions</h1>
          <p className="text-muted-foreground">Recent activity across all accounts.</p>
        </div>
        <AddTransactionModal accounts={accountOptions} categories={categoryOptions} />
      </div>

      {hasFilter && (
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-border bg-muted/40 px-4 py-3 text-sm">
          <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
            <span className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
              Filtered
            </span>
            {direction !== 'all' && (
              <span
                className={
                  direction === 'expense'
                    ? 'rounded-full border border-destructive/40 bg-destructive/10 px-2 py-0.5 text-[11px] font-medium text-destructive'
                    : 'rounded-full border border-emerald-500/40 bg-emerald-500/10 px-2 py-0.5 text-[11px] font-medium text-emerald-700 dark:text-emerald-300'
                }
              >
                {direction === 'expense' ? 'Expenses only' : 'Income only'}
              </span>
            )}
            {startDate && (
              <span className="text-muted-foreground">
                from{' '}
                <span className="font-medium text-foreground">
                  {longDateFormatter.format(startDate)}
                </span>
              </span>
            )}
            {endOfDay && (
              <span className="text-muted-foreground">
                to{' '}
                <span className="font-medium text-foreground">
                  {longDateFormatter.format(endOfDay)}
                </span>
              </span>
            )}
            <span className="text-muted-foreground">·</span>
            <span className="text-muted-foreground">
              <span className="font-medium text-foreground tabular-nums">{txns.length}</span> tx{' '}
              {filteredTotal !== null && (
                <>
                  totaling{' '}
                  <span className="font-mono font-medium text-foreground tabular-nums">
                    {formatCurrency(filteredTotal)}
                  </span>
                </>
              )}
            </span>
          </div>
          <Link
            href="/transactions"
            className="text-xs font-medium text-muted-foreground underline-offset-2 hover:text-foreground hover:underline"
          >
            Clear filter ✕
          </Link>
        </div>
      )}

      <Card>
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead className="w-28">Date</TableHead>
              <TableHead>Payee</TableHead>
              <TableHead>Account</TableHead>
              <TableHead>Category</TableHead>
              <TableHead className="text-right">Amount</TableHead>
              <TableHead className="w-12" aria-label="Actions" />
            </TableRow>
          </TableHeader>
          <TableBody>
            {txns.length === 0 ? (
              <TableRow>
                <TableCell colSpan={6} className="py-12 text-center text-muted-foreground">
                  {hasFilter
                    ? 'No transactions match this filter.'
                    : 'No transactions yet. Click "Add transaction" to get started.'}
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
                    <TableCell>
                      <TransactionCategoryCell
                        transactionId={t.id}
                        currentCategoryId={t.category?.id ?? null}
                        currentCategoryName={t.category?.name ?? null}
                        currentCategoryEmoji={t.category?.emoji ?? null}
                        options={categoryOptions}
                      />
                    </TableCell>
                    <TableCell
                      className={`text-right font-mono tabular-nums ${
                        isNegative ? 'text-destructive' : 'text-emerald-600'
                      }`}
                    >
                      {formatCurrencySigned(amount)}
                    </TableCell>
                    <TableCell className="text-right">
                      <DeleteTransactionButton transactionId={t.id} payee={t.payee} />
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
