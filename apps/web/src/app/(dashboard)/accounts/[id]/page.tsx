import { asc, eq } from 'drizzle-orm'
import Link from 'next/link'
import { notFound } from 'next/navigation'
import { AccountCardActions } from '@florin/core/components/accounts/account-card-actions'
import { LoanDetailsCard } from '@florin/core/components/accounts/loan-details-card'
import { AddTransactionModal } from '@florin/core/components/transactions/add-transaction-modal'
import { DeleteTransactionButton } from '@florin/core/components/transactions/delete-transaction-button'
import { TransactionCategoryCell } from '@florin/core/components/transactions/transaction-category-cell'
import { Badge } from '@florin/core/components/ui/badge'
import { buttonVariants } from '@florin/core/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@florin/core/components/ui/card'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@florin/core/components/ui/table'
import { db } from '@/db/client'
import { categories, categoryGroups } from '@/db/schema'
import { formatCurrency, formatCurrencySigned } from '@florin/core/lib/format'
import { computeLoanLiability } from '@/lib/loan/liability'
import { getServerT, getUserLocale } from '@/lib/locale'
import {
  getAccountById,
  listAccounts,
  deleteAccount,
  mergeAccount,
  setAccountArchived,
  updateLoanSettings,
} from '@/server/actions/accounts'
import { listCategoriesFlat, setCategoryLoanLink } from '@/server/actions/categories'
import {
  listLoanPaymentsForAccount,
  listTransactionsForAccount,
  addTransaction,
  addTransfer,
  softDeleteTransaction,
  updateTransactionCategory,
} from '@/server/actions/transactions'

interface AccountDetailPageProps {
  params: Promise<{ id: string }>
}

export default async function AccountDetailPage({ params }: AccountDetailPageProps) {
  const t = await getServerT()
  const locale = await getUserLocale()
  const localeTag = locale === 'fr' ? 'fr-FR' : 'en-US'
  const dateFormatter = new Intl.DateTimeFormat(localeTag, {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
  })
  const { id } = await params
  const account = await getAccountById(id)
  if (!account) notFound()

  const isLoan = account.kind === 'loan'
  const [transactionList, allAccounts, categoryList, categoriesFlat] = await Promise.all([
    isLoan
      ? listLoanPaymentsForAccount(account.id, 500)
      : listTransactionsForAccount(account.id, 500),
    listAccounts({ includeArchived: false }),
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
    listCategoriesFlat(),
  ])

  const inflow = transactionList
    .filter((t) => Number(t.amount) > 0)
    .reduce((acc, t) => acc + Number(t.amount), 0)
  const outflow = transactionList
    .filter((t) => Number(t.amount) < 0)
    .reduce((acc, t) => acc + Math.abs(Number(t.amount)), 0)

  const loanOriginPayments = isLoan ? transactionList.filter((t) => t.accountId !== account.id) : []
  const loanTotalPaid = loanOriginPayments.reduce((acc, t) => acc + Math.abs(Number(t.amount)), 0)
  const loanPrincipal = Number(account.loanOriginalPrincipal ?? 0)

  const loanBreakdown = isLoan
    ? computeLoanLiability(account, loanOriginPayments.length, loanTotalPaid)
    : null
  const loanRemainingDebt = loanBreakdown?.remainingDebt ?? 0
  const loanPrincipalPaid = loanBreakdown?.principalPaid ?? 0
  const loanInterestPaid = loanBreakdown?.interestPaid ?? 0

  const accountOptions = allAccounts.map((a) => ({
    id: a.id,
    name: a.name,
    currentBalance: Number(a.currentBalance),
  }))
  const mergeTargets = allAccounts
    .filter((a) => a.id !== account.id)
    .map((a) => ({ id: a.id, name: a.name }))

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="space-y-1">
          <Link
            href="/accounts"
            className="text-xs uppercase tracking-wide text-muted-foreground hover:text-foreground"
          >
            {t('accounts.backToAccounts', '← Accounts')}
          </Link>
          <h1 className="flex items-center gap-2 text-3xl font-bold tracking-tight">
            {account.displayIcon && <span aria-hidden>{account.displayIcon}</span>}
            {account.name}
          </h1>
          <div className="flex flex-wrap items-center gap-2 text-sm text-muted-foreground">
            <Badge variant="secondary">{account.kind}</Badge>
            {account.institution && <span>{account.institution}</span>}
            {account.iban && <span className="font-mono">{account.iban}</span>}
            {account.isArchived && (
              <span className="rounded-full border border-muted-foreground/30 bg-muted/30 px-2 py-0.5 text-[10px] font-medium uppercase">
                {t('accounts.archived', 'Archived')}
              </span>
            )}
          </div>
        </div>
        <div className="flex items-center gap-2">
          <AddTransactionModal
            accounts={accountOptions}
            categories={categoryList}
            defaultAccountId={account.id}
            triggerLabel={t('account.addTransactionTrigger', '+ Add transaction')}
            onAddTransaction={addTransaction}
            onAddTransfer={addTransfer}
          />
          <Link
            href={`/accounts/${account.id}/edit`}
            className={buttonVariants({ variant: 'outline', size: 'sm' })}
          >
            {t('common.edit', 'Edit')}
          </Link>
        </div>
      </div>

      {isLoan ? (
        <div className="grid gap-4 md:grid-cols-3">
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-xs uppercase tracking-wide text-muted-foreground">
                {t('account.loanRemaining', 'Remaining to repay')}
              </CardTitle>
            </CardHeader>
            <CardContent>
              <p className="text-3xl font-bold">{formatCurrency(loanRemainingDebt)}</p>
              {loanPrincipal > 0 && (
                <p className="mt-1 text-[11px] text-muted-foreground">
                  {t(
                    'account.loanRepaidPercent',
                    { percent: ((1 - loanRemainingDebt / loanPrincipal) * 100).toFixed(1) },
                    '{percent}% repaid',
                  )}
                </p>
              )}
            </CardContent>
          </Card>
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-xs uppercase tracking-wide text-muted-foreground">
                {t('account.loanRepaid', 'Already repaid')}
              </CardTitle>
            </CardHeader>
            <CardContent>
              <p className="text-3xl font-bold text-emerald-600">{formatCurrency(loanTotalPaid)}</p>
              <p className="mt-1 text-[11px] text-muted-foreground">
                {t(
                  'account.loanPaymentsApplied',
                  { count: loanOriginPayments.length },
                  '{count} payment(s) applied',
                )}
              </p>
              {(loanPrincipalPaid > 0 || loanInterestPaid > 0) && (
                <p className="mt-1 text-[11px] text-muted-foreground">
                  {t(
                    'account.loanPrincipalInterest',
                    {
                      principal: formatCurrency(loanPrincipalPaid),
                      interest: formatCurrency(loanInterestPaid),
                    },
                    '{principal} principal + {interest} interest',
                  )}
                </p>
              )}
            </CardContent>
          </Card>
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-xs uppercase tracking-wide text-muted-foreground">
                {t('account.loanInitial', 'Original amount')}
              </CardTitle>
            </CardHeader>
            <CardContent>
              <p className="text-3xl font-bold text-muted-foreground">
                {loanPrincipal > 0 ? formatCurrency(loanPrincipal) : '—'}
              </p>
              {account.loanInterestRate && (
                <p className="mt-1 text-[11px] text-muted-foreground">
                  {t(
                    'account.loanInterestRate',
                    { rate: (Number(account.loanInterestRate) * 100).toFixed(2) },
                    'Rate {rate} %',
                  )}
                </p>
              )}
            </CardContent>
          </Card>
        </div>
      ) : (
        <div className="grid gap-4 md:grid-cols-3">
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-xs uppercase tracking-wide text-muted-foreground">
                {t('accounts.currentBalance', 'Current balance')}
              </CardTitle>
            </CardHeader>
            <CardContent>
              <p className="text-3xl font-bold">{formatCurrency(account.currentBalance)}</p>
              {account.lastSyncedAt && (
                <p className="mt-1 text-[11px] text-muted-foreground">
                  {t(
                    'accounts.lastSynced',
                    { date: new Date(account.lastSyncedAt).toLocaleString(localeTag) },
                    'Last synced {date}',
                  )}
                </p>
              )}
            </CardContent>
          </Card>
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-xs uppercase tracking-wide text-muted-foreground">
                {t('accounts.inflow', { n: transactionList.length }, 'Inflow (last {n} tx)')}
              </CardTitle>
            </CardHeader>
            <CardContent>
              <p className="text-3xl font-bold text-emerald-600">{formatCurrency(inflow)}</p>
            </CardContent>
          </Card>
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-xs uppercase tracking-wide text-muted-foreground">
                {t('accounts.outflow', { n: transactionList.length }, 'Outflow (last {n} tx)')}
              </CardTitle>
            </CardHeader>
            <CardContent>
              <p className="text-3xl font-bold text-destructive">{formatCurrency(outflow)}</p>
            </CardContent>
          </Card>
        </div>
      )}

      {isLoan && (
        <LoanDetailsCard
          account={{
            id: account.id,
            currentBalance: account.currentBalance,
            loanOriginalPrincipal: account.loanOriginalPrincipal,
            loanInterestRate: account.loanInterestRate,
            loanStartDate: account.loanStartDate,
            loanTermMonths: account.loanTermMonths,
            loanMonthlyPayment: account.loanMonthlyPayment,
          }}
          categories={categoriesFlat}
          totalPaid={loanTotalPaid}
          remainingDebt={loanRemainingDebt}
          principalPaid={loanPrincipalPaid}
          interestPaid={loanInterestPaid}
          paymentsMade={loanOriginPayments.length}
          onUpdateLoanSettings={updateLoanSettings}
          onSetCategoryLoanLink={setCategoryLoanLink}
        />
      )}

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-base">
            {isLoan
              ? t('account.loanTitle', 'Loan payments')
              : t('account.transactions', 'Transactions')}
          </CardTitle>
          {isLoan && (
            <p className="text-[11px] text-muted-foreground">
              {t(
                'account.loanHint',
                'Transactions categorized in a category linked to this loan, plus manual adjustments on the loan account itself.',
              )}
            </p>
          )}
        </CardHeader>
        <CardContent className="p-0">
          {transactionList.length === 0 ? (
            <p className="px-4 py-12 text-center text-sm text-muted-foreground">
              {isLoan
                ? t(
                    'account.loanNoPayments',
                    'No payments yet. Link a category above and categorize your payments to see them here.',
                  )
                : t(
                    'account.noTransactions',
                    'No transactions yet. Click "+ Add transaction" above to record one.',
                  )}
            </p>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead className="w-28">{t('common.date', 'Date')}</TableHead>
                  <TableHead>{t('transactions.payee', 'Payee')}</TableHead>
                  <TableHead>{t('transactions.category', 'Category')}</TableHead>
                  <TableHead className="text-right">{t('common.amount', 'Amount')}</TableHead>
                  <TableHead className="w-12" aria-label={t('transactions.actions', 'Actions')} />
                </TableRow>
              </TableHeader>
              <TableBody>
                {transactionList.map((tx) => {
                  const amount = Number(tx.amount)
                  const isNegative = amount < 0
                  const noPayeeLabel = t('account.noPayee', '(no payee)')
                  return (
                    <TableRow key={tx.id}>
                      <TableCell className="font-mono text-xs text-muted-foreground">
                        {dateFormatter.format(tx.occurredAt)}
                      </TableCell>
                      <TableCell className="font-medium">
                        {tx.payee || noPayeeLabel}
                        {tx.needsReview && (
                          <span
                            className="ml-2 rounded-full border border-amber-500/40 bg-amber-500/10 px-1.5 py-0.5 text-[9px] font-medium uppercase tracking-wide text-amber-700 dark:text-amber-300"
                            title={t('account.reviewBadgeTitle', 'Pending review on /review')}
                          >
                            {t('account.reviewBadge', 'Review')}
                          </span>
                        )}
                      </TableCell>
                      <TableCell>
                        <TransactionCategoryCell
                          transactionId={tx.id}
                          currentCategoryId={tx.category?.id ?? null}
                          currentCategoryName={tx.category?.name ?? null}
                          currentCategoryEmoji={tx.category?.emoji ?? null}
                          options={categoryList}
                          onUpdateTransactionCategory={updateTransactionCategory}
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
                        <DeleteTransactionButton
                          transactionId={tx.id}
                          payee={tx.payee || noPayeeLabel}
                          onSoftDeleteTransaction={softDeleteTransaction}
                        />
                      </TableCell>
                    </TableRow>
                  )
                })}
              </TableBody>
            </Table>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-base">{t('accounts.manage', 'Manage')}</CardTitle>
        </CardHeader>
        <CardContent>
          <AccountCardActions
            accountId={account.id}
            accountName={account.name}
            isArchived={account.isArchived}
            hasBankSync={account.syncProvider === 'enable_banking'}
            mergeTargets={mergeTargets}
            onDeleteAccount={deleteAccount}
            onMergeAccount={mergeAccount}
            onSetAccountArchived={setAccountArchived}
          />
        </CardContent>
      </Card>
    </div>
  )
}
