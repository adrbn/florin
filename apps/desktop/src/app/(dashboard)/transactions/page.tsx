import { asc, eq } from 'drizzle-orm'
import { AddTransactionModal } from '@florin/core/components/transactions/add-transaction-modal'
import { TransactionsFilterBar } from '@florin/core/components/transactions/transactions-filter-bar'
import { TransactionsPager } from '@florin/core/components/transactions/transactions-pager'
import {
  type TransactionRowData,
  TransactionsTable,
} from '@florin/core/components/transactions/transactions-table'
import { Card } from '@florin/core/components/ui/card'
import { db } from '@/db/client'
import { categories, categoryGroups } from '@/db/schema'
import { formatCurrencySigned } from '@florin/core/lib/format'
import { listAccounts } from '@/server/actions/accounts'
import {
  addTransaction,
  countTransactions,
  listTransactions,
  softDeleteTransaction,
  updateTransactionCategory,
  type TransactionDirection,
} from '@/server/actions/transactions'

const PAGE_SIZE = 100

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

function parseAmount(raw: string | undefined): number | undefined {
  if (raw === undefined || raw === '') return undefined
  const n = Number(raw)
  return Number.isFinite(n) ? n : undefined
}

interface TransactionsPageProps {
  searchParams: Promise<{
    q?: string
    accountId?: string
    categoryId?: string
    from?: string
    to?: string
    direction?: string
    excludeTransfers?: string
    minAmount?: string
    maxAmount?: string
    page?: string
  }>
}

export default async function TransactionsPage({ searchParams }: TransactionsPageProps) {
  const sp = await searchParams
  const startDate = parseIsoDate(sp.from)
  const endOfDay = parseIsoDate(sp.to)
  const endDate = endOfDay
    ? new Date(endOfDay.getFullYear(), endOfDay.getMonth(), endOfDay.getDate(), 23, 59, 59, 999)
    : null
  const direction = parseDirection(sp.direction)
  const excludeTransfers = sp.excludeTransfers === '1' || sp.excludeTransfers === 'true'
  const payeeSearch = sp.q?.trim() || undefined
  const accountIdFilter = sp.accountId || undefined
  const categoryFilter: string | 'none' | undefined =
    sp.categoryId === 'none' ? 'none' : sp.categoryId || undefined
  const minAmount = parseAmount(sp.minAmount)
  const maxAmount = parseAmount(sp.maxAmount)
  const hasFilter = Boolean(
    startDate ||
      endDate ||
      direction !== 'all' ||
      excludeTransfers ||
      payeeSearch ||
      accountIdFilter ||
      categoryFilter ||
      minAmount !== undefined ||
      maxAmount !== undefined,
  )

  const pageNum = Math.max(1, Number.parseInt(sp.page ?? '1', 10) || 1)

  const filterOptions = {
    startDate: startDate?.toISOString() ?? undefined,
    endDate: endDate?.toISOString() ?? undefined,
    direction,
    excludeTransfers,
    payeeSearch,
    accountId: accountIdFilter,
    categoryId: categoryFilter,
    minAmount,
    maxAmount,
  }

  const [txns, totalCount, accountsList, categoryList] = await Promise.all([
    listTransactions({
      ...filterOptions,
      limit: PAGE_SIZE,
      offset: (pageNum - 1) * PAGE_SIZE,
    }),
    countTransactions(filterOptions),
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
  const filterBarAccounts = accountOptions
  const filterBarCategories = categoryList.map((c) => ({
    id: c.id,
    name: c.name,
    emoji: c.emoji,
    groupName: c.groupName ?? 'Other',
  }))

  const filteredTotal = hasFilter ? txns.reduce((acc, t) => acc + Number(t.amount), 0) : null

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Transactions</h1>
          <p className="text-muted-foreground">Recent activity across all accounts.</p>
        </div>
        <AddTransactionModal
          accounts={accountOptions}
          categories={categoryOptions}
          onAddTransaction={addTransaction}
        />
      </div>

      <TransactionsFilterBar accounts={filterBarAccounts} categories={filterBarCategories} />

      {hasFilter && (
        <div className="flex flex-wrap items-center gap-x-3 gap-y-1 rounded-md border border-border/60 bg-muted/30 px-3 py-2 text-[11px] text-muted-foreground">
          <span className="font-semibold uppercase tracking-wide">Active filter</span>
          {direction !== 'all' && (
            <span
              className={
                direction === 'expense'
                  ? 'rounded-full border border-destructive/40 bg-destructive/10 px-2 py-0.5 font-medium text-destructive'
                  : 'rounded-full border border-emerald-500/40 bg-emerald-500/10 px-2 py-0.5 font-medium text-emerald-700 dark:text-emerald-300'
              }
            >
              {direction === 'expense' ? 'Expenses only' : 'Income only'}
            </span>
          )}
          {startDate && (
            <span>
              from{' '}
              <span className="font-medium text-foreground">
                {longDateFormatter.format(startDate)}
              </span>
            </span>
          )}
          {endOfDay && (
            <span>
              to{' '}
              <span className="font-medium text-foreground">
                {longDateFormatter.format(endOfDay)}
              </span>
            </span>
          )}
          <span>
            ·{' '}
            <span className="font-medium text-foreground tabular-nums">
              {totalCount.toLocaleString('fr-FR')}
            </span>{' '}
            matching tx{' '}
            {filteredTotal !== null && (
              <>
                · current page totals{' '}
                <span className="font-medium text-foreground tabular-nums">
                  {formatCurrencySigned(filteredTotal)}
                </span>
              </>
            )}
          </span>
        </div>
      )}

      <Card className="p-0">
        <TransactionsTable
          rows={txns.map(
            (t): TransactionRowData => ({
              id: t.id,
              date: dateFormatter.format(t.occurredAt),
              payee: t.payee,
              accountName: t.account?.name ?? '—',
              amount: Number(t.amount),
              currentCategoryId: t.category?.id ?? null,
              currentCategoryName: t.category?.name ?? null,
              currentCategoryEmoji: t.category?.emoji ?? null,
            }),
          )}
          categoryOptions={categoryOptions}
          emptyMessage={
            hasFilter
              ? 'No transactions match this filter.'
              : 'No transactions yet. Click "Add transaction" to get started.'
          }
          actions={{
            onUpdateTransactionCategory: updateTransactionCategory,
            onSoftDeleteTransaction: softDeleteTransaction,
          }}
        />
        <TransactionsPager page={pageNum} pageSize={PAGE_SIZE} totalCount={totalCount} />
      </Card>
    </div>
  )
}
