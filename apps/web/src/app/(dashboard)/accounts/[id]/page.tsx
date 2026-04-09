import { asc, eq } from 'drizzle-orm'
import Link from 'next/link'
import { notFound } from 'next/navigation'
import { AccountCardActions } from '@/components/accounts/account-card-actions'
import { LoanDetailsCard } from '@/components/accounts/loan-details-card'
import { AddTransactionModal } from '@/components/transactions/add-transaction-modal'
import { DeleteTransactionButton } from '@/components/transactions/delete-transaction-button'
import { TransactionCategoryCell } from '@/components/transactions/transaction-category-cell'
import { Badge } from '@/components/ui/badge'
import { buttonVariants } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
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
import { computeTermMonths, type LoanInputs, simulateSchedule } from '@/lib/loan/amortization'
import { getAccountById, listAccounts } from '@/server/actions/accounts'
import { listCategoriesFlat } from '@/server/actions/categories'
import {
  listLoanPaymentsForAccount,
  listTransactionsForAccount,
} from '@/server/actions/transactions'

const dateFormatter = new Intl.DateTimeFormat('fr-FR', {
  day: '2-digit',
  month: '2-digit',
  year: 'numeric',
})

interface AccountDetailPageProps {
  params: Promise<{ id: string }>
}

export default async function AccountDetailPage({ params }: AccountDetailPageProps) {
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

  // Quick stats derived from the in-memory transaction list — cheap because
  // we cap at 500 rows and the page is per-account.
  const inflow = transactionList
    .filter((t) => Number(t.amount) > 0)
    .reduce((acc, t) => acc + Number(t.amount), 0)
  const outflow = transactionList
    .filter((t) => Number(t.amount) < 0)
    .reduce((acc, t) => acc + Math.abs(Number(t.amount)), 0)

  // Loan-specific derived numbers.
  // `totalPaid` = sum of |amount| for every real payment (non-mirror rows
  // living on an origin account like checking) that's categorized under a
  // category linked to this loan. Manual adjustments living on the loan row
  // itself are excluded — they're balance corrections, not payments.
  const loanOriginPayments = isLoan ? transactionList.filter((t) => t.accountId !== account.id) : []
  const loanTotalPaid = loanOriginPayments.reduce((acc, t) => acc + Math.abs(Number(t.amount)), 0)
  const loanPrincipal = Number(account.loanOriginalPrincipal ?? 0)

  // `remainingDebt` = balance from the amortization schedule after
  // `paymentsMade` mensualités. This matches what the bank reports (capital
  // restant dû) and correctly accounts for interest accrual instead of the
  // naive `principal − totalPaid` subtraction. We also split totalPaid
  // into principal + interest so the UI can show a real breakdown.
  //
  // Falls back to the naive formula when the loan parameters aren't
  // complete enough to build a schedule — keeps the detail page useful
  // during initial setup before the user has filled in rate/term/start.
  const loanBreakdown = isLoan
    ? computeLoanBreakdown({
        principal: loanPrincipal,
        annualRate: Number(account.loanInterestRate ?? 0),
        termMonths: account.loanTermMonths,
        monthlyPayment: Number(account.loanMonthlyPayment ?? 0),
        startDate: account.loanStartDate,
        paymentsMade: loanOriginPayments.length,
        totalPaidFallback: loanTotalPaid,
      })
    : null
  const loanRemainingDebt = loanBreakdown?.remainingDebt ?? 0
  const loanPrincipalPaid = loanBreakdown?.principalPaid ?? 0
  const loanInterestPaid = loanBreakdown?.interestPaid ?? 0

  const accountOptions = allAccounts.map((a) => ({ id: a.id, name: a.name }))
  // Every *other* non-archived account — the merge picker needs them.
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
            ← Accounts
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
                Archived
              </span>
            )}
          </div>
        </div>
        <div className="flex items-center gap-2">
          <AddTransactionModal
            accounts={accountOptions}
            categories={categoryList}
            defaultAccountId={account.id}
            triggerLabel="+ Add transaction"
          />
          <Link
            href={`/accounts/${account.id}/edit`}
            className={buttonVariants({ variant: 'outline', size: 'sm' })}
          >
            Edit
          </Link>
        </div>
      </div>

      {isLoan ? (
        <div className="grid gap-4 md:grid-cols-3">
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-xs uppercase tracking-wide text-muted-foreground">
                Restant à rembourser
              </CardTitle>
            </CardHeader>
            <CardContent>
              <p className="text-3xl font-bold">{formatCurrency(loanRemainingDebt)}</p>
              {loanPrincipal > 0 && (
                <p className="mt-1 text-[11px] text-muted-foreground">
                  {((1 - loanRemainingDebt / loanPrincipal) * 100).toFixed(1)}% remboursé
                </p>
              )}
            </CardContent>
          </Card>
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-xs uppercase tracking-wide text-muted-foreground">
                Déjà remboursé
              </CardTitle>
            </CardHeader>
            <CardContent>
              <p className="text-3xl font-bold text-emerald-600">{formatCurrency(loanTotalPaid)}</p>
              <p className="mt-1 text-[11px] text-muted-foreground">
                {loanOriginPayments.length} paiement(s) appliqué(s)
              </p>
              {(loanPrincipalPaid > 0 || loanInterestPaid > 0) && (
                <p className="mt-1 text-[11px] text-muted-foreground">
                  {formatCurrency(loanPrincipalPaid)} capital + {formatCurrency(loanInterestPaid)}{' '}
                  intérêts
                </p>
              )}
            </CardContent>
          </Card>
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-xs uppercase tracking-wide text-muted-foreground">
                Montant initial
              </CardTitle>
            </CardHeader>
            <CardContent>
              <p className="text-3xl font-bold text-muted-foreground">
                {loanPrincipal > 0 ? formatCurrency(loanPrincipal) : '—'}
              </p>
              {account.loanInterestRate && (
                <p className="mt-1 text-[11px] text-muted-foreground">
                  Taux {(Number(account.loanInterestRate) * 100).toFixed(2)} %
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
                Current balance
              </CardTitle>
            </CardHeader>
            <CardContent>
              <p className="text-3xl font-bold">{formatCurrency(account.currentBalance)}</p>
              {account.lastSyncedAt && (
                <p className="mt-1 text-[11px] text-muted-foreground">
                  Last synced {new Date(account.lastSyncedAt).toLocaleString('fr-FR')}
                </p>
              )}
            </CardContent>
          </Card>
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-xs uppercase tracking-wide text-muted-foreground">
                Inflow (last {transactionList.length} tx)
              </CardTitle>
            </CardHeader>
            <CardContent>
              <p className="text-3xl font-bold text-emerald-600">{formatCurrency(inflow)}</p>
            </CardContent>
          </Card>
          <Card>
            <CardHeader className="pb-2">
              <CardTitle className="text-xs uppercase tracking-wide text-muted-foreground">
                Outflow (last {transactionList.length} tx)
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
        />
      )}

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-base">
            {isLoan ? 'Paiements sur ce prêt' : 'Transactions'}
          </CardTitle>
          {isLoan && (
            <p className="text-[11px] text-muted-foreground">
              Transactions catégorisées dans une catégorie liée à ce prêt, plus les ajustements
              manuels sur le compte prêt lui-même.
            </p>
          )}
        </CardHeader>
        <CardContent className="p-0">
          {transactionList.length === 0 ? (
            <p className="px-4 py-12 text-center text-sm text-muted-foreground">
              {isLoan
                ? 'Aucun paiement pour le moment. Liez une catégorie ci-dessus et catégorisez vos paiements pour les voir ici.'
                : 'No transactions yet. Click "+ Add transaction" above to record one.'}
            </p>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead className="w-28">Date</TableHead>
                  <TableHead>Payee</TableHead>
                  <TableHead>Category</TableHead>
                  <TableHead className="text-right">Amount</TableHead>
                  <TableHead className="w-12" aria-label="Actions" />
                </TableRow>
              </TableHeader>
              <TableBody>
                {transactionList.map((t) => {
                  const amount = Number(t.amount)
                  const isNegative = amount < 0
                  return (
                    <TableRow key={t.id}>
                      <TableCell className="font-mono text-xs text-muted-foreground">
                        {dateFormatter.format(t.occurredAt)}
                      </TableCell>
                      <TableCell className="font-medium">
                        {t.payee || '(no payee)'}
                        {t.needsReview && (
                          <span
                            className="ml-2 rounded-full border border-amber-500/40 bg-amber-500/10 px-1.5 py-0.5 text-[9px] font-medium uppercase tracking-wide text-amber-700 dark:text-amber-300"
                            title="Pending review on /review"
                          >
                            Review
                          </span>
                        )}
                      </TableCell>
                      <TableCell>
                        <TransactionCategoryCell
                          transactionId={t.id}
                          currentCategoryId={t.category?.id ?? null}
                          currentCategoryName={t.category?.name ?? null}
                          currentCategoryEmoji={t.category?.emoji ?? null}
                          options={categoryList}
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
                          transactionId={t.id}
                          payee={t.payee || '(no payee)'}
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
          <CardTitle className="text-base">Manage</CardTitle>
        </CardHeader>
        <CardContent>
          <AccountCardActions
            accountId={account.id}
            accountName={account.name}
            isArchived={account.isArchived}
            hasBankSync={account.syncProvider === 'enable_banking'}
            mergeTargets={mergeTargets}
          />
        </CardContent>
      </Card>
    </div>
  )
}

interface LoanBreakdownInput {
  principal: number
  annualRate: number
  termMonths: number | null
  monthlyPayment: number
  startDate: Date | string | null
  paymentsMade: number
  totalPaidFallback: number
}

interface LoanBreakdown {
  remainingDebt: number
  principalPaid: number
  interestPaid: number
}

/**
 * Compute the "real" restant dû by walking the amortization schedule to the
 * number of mensualités already paid. When we have all loan parameters, the
 * schedule's `balanceAfter` at that index matches the bank's capital restant
 * dû (±1€ rounding). Also returns the principal/interest split of the money
 * the user has actually sent so far — useful for a "Déjà remboursé" tile
 * that shows "2 366 € capital + 624 € intérêts" instead of a flat total.
 *
 * Falls back to `{ remainingDebt: principal − totalPaid, principalPaid:
 * totalPaid, interestPaid: 0 }` when the params aren't complete enough to
 * build a schedule — keeps the detail page usable during loan setup.
 */
function computeLoanBreakdown(input: LoanBreakdownInput): LoanBreakdown {
  const {
    principal,
    annualRate,
    termMonths,
    monthlyPayment,
    startDate,
    paymentsMade,
    totalPaidFallback,
  } = input

  const fallback: LoanBreakdown = {
    remainingDebt: Math.max(0, principal - totalPaidFallback),
    principalPaid: totalPaidFallback,
    interestPaid: 0,
  }

  if (principal <= 0 || annualRate < 0) return fallback
  const start = startDate ? new Date(startDate) : null
  if (!start || Number.isNaN(start.getTime())) return fallback

  // Need a term — use the stored one when present, otherwise derive from
  // the monthly payment (mirrors what loan-details-card.tsx does on the
  // client side so both views agree on the schedule).
  let term = termMonths && termMonths > 0 ? termMonths : 0
  if (term <= 0) {
    if (!Number.isFinite(monthlyPayment) || monthlyPayment <= 0) return fallback
    const derived = computeTermMonths({
      originalPrincipal: principal,
      annualRate,
      monthlyPayment,
    })
    if (!derived) return fallback
    term = derived
  }

  const loanInputs: LoanInputs = {
    originalPrincipal: principal,
    annualRate,
    termMonths: term,
    startDate: start,
  }

  // Use the stored mensualité as the override when set — banks round the
  // payment slightly differently from our formula (e.g. 135.91€ vs
  // 136.30€) and the resulting balance differs by ~15€ over 2 years.
  const baseMonthlyPayment =
    Number.isFinite(monthlyPayment) && monthlyPayment > 0 ? monthlyPayment : undefined
  const schedule = simulateSchedule(loanInputs, { baseMonthlyPayment })

  if (paymentsMade <= 0) {
    return {
      remainingDebt: principal,
      principalPaid: 0,
      interestPaid: 0,
    }
  }

  // Clamp the cursor to the schedule length. If the user has somehow
  // applied more mensualités than the contract lists (e.g. early-repay
  // simulator disabled the last few rows), the schedule already ends at
  // balance 0 so we just read the tail.
  const cursor = Math.min(paymentsMade, schedule.rows.length) - 1
  const row = schedule.rows[cursor]
  if (!row) return fallback

  const paidRows = schedule.rows.slice(0, cursor + 1)
  const principalPaid = paidRows.reduce((sum, r) => sum + r.principal + r.extraPayment, 0)
  const interestPaid = paidRows.reduce((sum, r) => sum + r.interest, 0)

  return {
    remainingDebt: Math.max(0, row.balanceAfter),
    principalPaid,
    interestPaid,
  }
}
