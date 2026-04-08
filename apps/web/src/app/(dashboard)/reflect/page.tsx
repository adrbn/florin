import { CategoryBreakdownChart } from '@/components/reflect/category-breakdown-chart'
import { IncomeVsSpendingChart } from '@/components/reflect/income-vs-spending-chart'
import { NetWorthChart } from '@/components/reflect/net-worth-chart'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { formatCurrency } from '@/lib/format/currency'
import { getNetWorth } from '@/server/queries/dashboard'
import {
  getAgeOfMoney,
  getCategoryBreakdown,
  getMonthlyFlows,
  getNetWorthSeries,
} from '@/server/queries/reflect'

// Reflect reads from the database on every render — never prerender it at
// build time, otherwise the user would see frozen numbers from the moment
// the image was built.
export const dynamic = 'force-dynamic'

/**
 * Reflect — analytics tab. Lays out four charts plus a small KPI strip.
 * Everything is server-rendered so the user gets fresh numbers on every
 * page load with no client-side fetching.
 */
export default async function ReflectPage() {
  const [flows, categoryShare, ageOfMoney, netWorthSeries, netWorth] = await Promise.all([
    getMonthlyFlows(12),
    getCategoryBreakdown(90),
    getAgeOfMoney(90),
    getNetWorthSeries(24),
    getNetWorth(),
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
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Reflect</h1>
        <p className="text-muted-foreground">
          Long-window analytics — how your money has actually moved.
        </p>
      </div>

      <div className="grid gap-4 md:grid-cols-4">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-xs uppercase tracking-wide text-muted-foreground">
              Net worth
            </CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-2xl font-bold">{formatCurrency(netWorth.net)}</p>
            <p className="mt-1 text-[11px] text-muted-foreground">
              Gross {formatCurrency(netWorth.gross)}
            </p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-xs uppercase tracking-wide text-muted-foreground">
              Income (12mo)
            </CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-2xl font-bold text-emerald-600">{formatCurrency(last12.income)}</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-xs uppercase tracking-wide text-muted-foreground">
              Spending (12mo)
            </CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-2xl font-bold text-destructive">{formatCurrency(last12.expense)}</p>
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-xs uppercase tracking-wide text-muted-foreground">
              Age of money
            </CardTitle>
          </CardHeader>
          <CardContent>
            <p className="text-2xl font-bold">
              {ageOfMoney === null ? '—' : `${Math.round(ageOfMoney)} d`}
            </p>
            <p className="mt-1 text-[11px] text-muted-foreground">
              {savingsRate >= 0 ? '+' : ''}
              {savingsRate.toFixed(0)}% savings rate
            </p>
          </CardContent>
        </Card>
      </div>

      <div className="grid gap-6 lg:grid-cols-2">
        <IncomeVsSpendingChart data={flows} />
        <NetWorthChart data={netWorthSeries} />
      </div>

      <CategoryBreakdownChart data={categoryShare} windowLabel="last 90 days" />
    </div>
  )
}
