import { CategoryBreakdownChart } from '@florin/core/components/reflect/category-breakdown-chart'
import { IncomeVsSpendingChart } from '@florin/core/components/reflect/income-vs-spending-chart'
import { NetWorthChart } from '@florin/core/components/reflect/net-worth-chart'
import { Card, CardContent, CardHeader, CardTitle } from '@florin/core/components/ui/card'
import { formatCurrency } from '@florin/core/lib/format'
import { queries } from '@/db/client'
import { detectRecurringTransactions } from '@/server/actions/recurring'
import { RecurringList } from '@/components/recurring-list'
import { PdfExportButton } from '@/components/pdf-export-button'

// Reflect reads from the database on every render — never prerender it at
// build time, otherwise the user would see frozen numbers from the moment
// the image was built.
export const dynamic = 'force-dynamic'

/**
 * Reflect — analytics tab. Lays out a KPI strip plus three charts (income
 * vs spending, net worth, category breakdown). The whole page is designed
 * to fit in a single viewport on desktop — same min-h-0 / flex pattern as
 * the Dashboard — so the user doesn't have to scroll to see everything.
 * On mobile we fall back to a natural vertical scroll.
 */
export default async function ReflectPage() {
  const [flows, categoryShare, ageOfMoney, netWorthSeries, netWorth, recurring] = await Promise.all([
    queries.getMonthlyFlows(12),
    queries.getCategoryBreakdown(90),
    queries.getAgeOfMoney(90),
    queries.getNetWorthSeries(24),
    queries.getNetWorth(),
    detectRecurringTransactions(),
  ])

  const last12 = flows.reduce(
    (acc, f) => ({
      income: acc.income + f.income,
      expense: acc.expense + f.expense,
    }),
    { income: 0, expense: 0 },
  )
  const savingsRate =
    last12.income > 0 ? ((last12.income - last12.expense) / last12.income) * 100 : 0

  return (
    <div className="space-y-3">
      <header className="flex items-start justify-between gap-4">
        <div className="min-w-0">
          <h1 className="text-xl font-semibold tracking-tight sm:text-2xl">Reflect</h1>
          <p className="mt-0.5 text-xs text-muted-foreground">
            Long-window analytics — how your money has actually moved.
          </p>
        </div>
        <PdfExportButton />
      </header>

      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        <Card className="gap-1 py-3">
          <CardHeader className="px-4 py-0">
            <CardTitle className="text-[10px] uppercase tracking-wide text-muted-foreground">
              Net worth
            </CardTitle>
          </CardHeader>
          <CardContent className="px-4 py-0">
            <p className="text-xl font-bold tabular-nums">{formatCurrency(netWorth.net)}</p>
            <p className="mt-0.5 text-[10px] text-muted-foreground">
              Gross {formatCurrency(netWorth.gross)}
            </p>
          </CardContent>
        </Card>
        <Card className="gap-1 py-3">
          <CardHeader className="px-4 py-0">
            <CardTitle className="text-[10px] uppercase tracking-wide text-muted-foreground">
              Income (12mo)
            </CardTitle>
          </CardHeader>
          <CardContent className="px-4 py-0">
            <p className="text-xl font-bold tabular-nums text-emerald-600 dark:text-emerald-400">
              {formatCurrency(last12.income)}
            </p>
          </CardContent>
        </Card>
        <Card className="gap-1 py-3">
          <CardHeader className="px-4 py-0">
            <CardTitle className="text-[10px] uppercase tracking-wide text-muted-foreground">
              Spending (12mo)
            </CardTitle>
          </CardHeader>
          <CardContent className="px-4 py-0">
            <p className="text-xl font-bold tabular-nums text-destructive">
              {formatCurrency(last12.expense)}
            </p>
          </CardContent>
        </Card>
        <Card className="gap-1 py-3">
          <CardHeader className="px-4 py-0">
            <CardTitle className="text-[10px] uppercase tracking-wide text-muted-foreground">
              Age of money
            </CardTitle>
          </CardHeader>
          <CardContent className="px-4 py-0">
            <p className="text-xl font-bold tabular-nums">
              {ageOfMoney === null ? '—' : `${Math.round(ageOfMoney)} d`}
            </p>
            <p className="mt-0.5 text-[10px] text-muted-foreground">
              {savingsRate >= 0 ? '+' : ''}
              {savingsRate.toFixed(0)}% savings rate
            </p>
          </CardContent>
        </Card>
      </div>

      <div className="grid grid-cols-1 gap-3 lg:grid-cols-12">
        <div className="min-h-[320px] lg:col-span-7">
          <IncomeVsSpendingChart data={flows} />
        </div>
        <div className="min-h-[320px] lg:col-span-5">
          <NetWorthChart data={netWorthSeries} />
        </div>
        <div className="min-h-[320px] lg:col-span-12">
          <CategoryBreakdownChart data={categoryShare} windowLabel="last 90 days" />
        </div>
      </div>

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-base">Recurring Expenses</CardTitle>
          <p className="text-xs text-muted-foreground">
            Auto-detected repeating payments based on payee frequency patterns.
          </p>
        </CardHeader>
        <CardContent>
          <RecurringList patterns={recurring} />
        </CardContent>
      </Card>
    </div>
  )
}
