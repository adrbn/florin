import { NextResponse } from 'next/server'
import { queries } from '@/db/client'
import type {
  MonthlyFlow,
  NetWorthPoint,
  CategorySpendingSeries,
} from '@florin/core/types'

export const dynamic = 'force-dynamic'

/**
 * Multi-page printable finance report.
 *
 * Serves a stand-alone HTML page the client opens and prints via the
 * browser's `window.print()` — no external PDF library, no server-side
 * Chromium. Major sections (`h2.section`) start on a fresh page, cards and
 * table rows use `page-break-inside: avoid` so nothing gets sliced across a
 * page boundary. Charts are inline SVG so they render identically in the
 * browser preview and the printed output.
 *
 * The `?month=YYYY-MM` query param scopes the monthly narrative to a
 * specific month; everything else is long-window (12/24 months) and stable.
 */
export async function GET(request: Request) {
  const { searchParams } = new URL(request.url)
  const monthParam = searchParams.get('month')
  const now = new Date()
  const year = monthParam ? parseInt(monthParam.split('-')[0]!, 10) : now.getFullYear()
  const mon = monthParam ? parseInt(monthParam.split('-')[1]!, 10) : now.getMonth() + 1
  const monthKey = `${year}-${String(mon).padStart(2, '0')}`

  const monthLabel = new Date(year, mon - 1, 1).toLocaleDateString('fr-FR', {
    month: 'long',
    year: 'numeric',
  })

  const [
    netWorth,
    flows,
    categoryBreakdown,
    topExpenses,
    netWorthSeries,
    categoryTrends,
    subscriptions,
    savingsRates,
    leftToSpend,
    ageOfMoney,
  ] = await Promise.all([
    queries.getNetWorth(),
    queries.getMonthlyFlows(12),
    queries.getCategoryBreakdown(30),
    queries.getTopExpenses(20, 31),
    queries.getNetWorthSeries(24),
    queries.getCategorySpendingSeries(12),
    queries.getSubscriptions(),
    queries.getSavingsRates(),
    queries.getLeftToSpendThisMonth(),
    queries.getAgeOfMoney(90),
  ])

  // Month-scoped figures — pick the flow row for the requested month, or
  // fall back to whatever the latest row is if the month isn't in the window
  // (e.g. archived months). Prevents a blank cover for historical exports.
  const monthFlow =
    flows.find((f) => f.month === monthKey) ?? flows[flows.length - 1] ?? {
      month: monthKey,
      income: 0,
      expense: 0,
      net: 0,
    }
  const income = monthFlow.income
  const expense = monthFlow.expense
  const net = income - expense
  const savingsPct = income > 0 ? (net / income) * 100 : null

  // 12-month totals for the "year so far" framing on the cover.
  const last12 = flows.reduce(
    (acc, f) => ({
      income: acc.income + f.income,
      expense: acc.expense + f.expense,
    }),
    { income: 0, expense: 0 },
  )
  const last12Net = last12.income - last12.expense
  const last12SavingsPct =
    last12.income > 0 ? (last12Net / last12.income) * 100 : null

  const verdict = buildVerdict({
    net,
    savingsPct,
    last12SavingsPct,
    overspentCategories: categoryBreakdown.filter((c) => c.total > 500).length,
    subsAnnual: subscriptions.reduce((s, x) => s + x.annualCost, 0),
  })

  const totalCategorySpend = categoryBreakdown.reduce((s, c) => s + c.total, 0)

  // Flags (actionable insights). Mix of category-level spikes and recurring
  // detection. Keep to 6 max so the page doesn't sprawl.
  const flags = buildFlags({
    categoryTrends,
    subscriptions,
    savingsRates,
    last12SavingsPct,
  }).slice(0, 6)

  const html = `<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <title>Florin — ${esc(monthLabel)}</title>
  <style>${CSS}</style>
</head>
<body>
  <button class="print-btn" onclick="window.print()">Save as PDF</button>

  <!-- =============== COVER =============== -->
  <section class="page cover">
    <div class="cover-brand">Florin</div>
    <h1>Finance report</h1>
    <p class="cover-month">${esc(monthLabel)}</p>
    <div class="cover-verdict">${esc(verdict)}</div>
    <div class="cover-hero">
      <div class="hero-kpi">
        <div class="hero-label">Net worth</div>
        <div class="hero-value">${fmt(netWorth.net)}</div>
        <div class="hero-sub">Gross ${fmt(netWorth.gross)} · Debts ${fmt(netWorth.liability)}</div>
      </div>
      <div class="hero-kpi">
        <div class="hero-label">Savings rate (12 mo)</div>
        <div class="hero-value ${(last12SavingsPct ?? 0) >= 0 ? 'positive' : 'negative'}">
          ${last12SavingsPct === null ? '—' : `${last12SavingsPct >= 0 ? '+' : ''}${last12SavingsPct.toFixed(0)}%`}
        </div>
        <div class="hero-sub">${fmt(last12Net)} saved of ${fmt(last12.income)}</div>
      </div>
    </div>
    <div class="cover-footer">
      Generated ${new Date().toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', year: 'numeric' })} · florin.app
    </div>
  </section>

  <!-- =============== KPI SNAPSHOT =============== -->
  <section class="page">
    <h2 class="section">Snapshot — ${esc(monthLabel)}</h2>
    <div class="kpi-grid">
      <div class="kpi">
        <div class="kpi-label">Income</div>
        <div class="kpi-value positive">${fmt(income)}</div>
      </div>
      <div class="kpi">
        <div class="kpi-label">Expenses</div>
        <div class="kpi-value negative">${fmt(expense)}</div>
      </div>
      <div class="kpi">
        <div class="kpi-label">Net this month</div>
        <div class="kpi-value ${net >= 0 ? 'positive' : 'negative'}">${fmt(net)}</div>
      </div>
      <div class="kpi">
        <div class="kpi-label">Savings rate</div>
        <div class="kpi-value ${(savingsPct ?? 0) >= 0 ? 'positive' : 'negative'}">
          ${savingsPct === null ? '—' : `${savingsPct >= 0 ? '+' : ''}${savingsPct.toFixed(0)}%`}
        </div>
      </div>
    </div>

    <div class="kpi-grid">
      <div class="kpi">
        <div class="kpi-label">Left to spend</div>
        <div class="kpi-value ${leftToSpend.leftToSpend >= 0 ? 'positive' : 'negative'}">${fmt(leftToSpend.leftToSpend)}</div>
        <div class="kpi-sub">${leftToSpend.daysRemaining} days remaining${
          leftToSpend.dailyBudgetRemaining !== null
            ? ` · ${fmt(leftToSpend.dailyBudgetRemaining)}/day`
            : ''
        }</div>
      </div>
      <div class="kpi">
        <div class="kpi-label">Age of money</div>
        <div class="kpi-value">${ageOfMoney === null ? '—' : `${Math.round(ageOfMoney)} d`}</div>
        <div class="kpi-sub">How many days old each euro you spend is.</div>
      </div>
      <div class="kpi">
        <div class="kpi-label">Savings — 3 / 6 / 12 mo</div>
        <div class="kpi-value small">
          ${pctCell(savingsRates.threeMonth)} · ${pctCell(savingsRates.sixMonth)} · ${pctCell(savingsRates.twelveMonth)}
        </div>
      </div>
      <div class="kpi">
        <div class="kpi-label">Subscriptions (annualised)</div>
        <div class="kpi-value negative">${fmt(subscriptions.reduce((s, x) => s + x.annualCost, 0))}</div>
        <div class="kpi-sub">${subscriptions.length} recurring charge${subscriptions.length === 1 ? '' : 's'} detected</div>
      </div>
    </div>

    ${flags.length > 0 ? `
    <h3 class="subsection">What to look at</h3>
    <ul class="flags">
      ${flags.map((f) => `<li class="flag flag-${f.severity}"><span class="flag-dot"></span><div><strong>${esc(f.title)}</strong><br><span class="flag-body">${esc(f.body)}</span></div></li>`).join('')}
    </ul>
    ` : ''}
  </section>

  <!-- =============== INCOME vs SPENDING =============== -->
  <section class="page">
    <h2 class="section">Income vs spending — last 12 months</h2>
    <p class="section-lede">Green bars = income in that month, red = expenses. The thin line is the net (savings, or burn when it dips below zero).</p>
    <div class="chart">${renderFlowsChart(flows)}</div>
    <table>
      <thead><tr><th>Month</th><th class="amount">Income</th><th class="amount">Expenses</th><th class="amount">Net</th></tr></thead>
      <tbody>
        ${flows
          .slice()
          .reverse()
          .map(
            (f) => `<tr>
          <td>${esc(formatMonthLong(f.month))}</td>
          <td class="amount positive">${fmt(f.income)}</td>
          <td class="amount negative">${fmt(f.expense)}</td>
          <td class="amount ${f.net >= 0 ? 'positive' : 'negative'}">${fmt(f.net)}</td>
        </tr>`,
          )
          .join('')}
      </tbody>
    </table>
  </section>

  <!-- =============== NET WORTH TREND =============== -->
  <section class="page">
    <h2 class="section">Net worth — last 24 months</h2>
    <p class="section-lede">Cumulative balance across all tracked accounts. The value at each month is a month-end snapshot.</p>
    <div class="chart">${renderNetWorthChart(netWorthSeries)}</div>
    ${buildNetWorthNarrative(netWorthSeries)}
  </section>

  <!-- =============== CATEGORY TRENDS =============== -->
  <section class="page">
    <h2 class="section">Spending by category — last 12 months</h2>
    <p class="section-lede">Top 8 categories by total spend. A rising line means you're spending more there over time.</p>
    <div class="chart">${renderCategoryTrendsChart(categoryTrends, 8)}</div>
    <div class="chart-legend">
      ${categoryTrends.categories
        .slice(0, 8)
        .map(
          (c, i) => `<span class="legend-chip"><span class="legend-dot" style="background:${PALETTE[i % PALETTE.length]}"></span>${esc(c.emoji ? c.emoji + ' ' : '')}${esc(c.categoryName)} <em>${fmt(c.total)}</em></span>`,
        )
        .join('')}
    </div>
  </section>

  <!-- =============== CATEGORY BREAKDOWN =============== -->
  <section class="page">
    <h2 class="section">Spending breakdown — last 30 days</h2>
    <p class="section-lede">Categories ranked by spend this month, with the share of total and an annualised projection if this rate held.</p>
    <table>
      <thead>
        <tr>
          <th>Category</th>
          <th>Group</th>
          <th class="amount">30 days</th>
          <th class="amount">Share</th>
          <th class="amount">Annualised</th>
        </tr>
      </thead>
      <tbody>
        ${categoryBreakdown
          .map((c) => {
            const share = totalCategorySpend > 0 ? (c.total / totalCategorySpend) * 100 : 0
            const annual = c.total * (365 / 30)
            return `<tr>
              <td>${esc(c.emoji ? c.emoji + ' ' : '')}${esc(c.categoryName)}</td>
              <td class="muted">${esc(c.groupName)}</td>
              <td class="amount negative">${fmt(c.total)}</td>
              <td class="amount">${share.toFixed(1)}%</td>
              <td class="amount muted">${fmt(annual)}</td>
            </tr>`
          })
          .join('')}
      </tbody>
      <tfoot>
        <tr>
          <td colspan="2"><strong>Total</strong></td>
          <td class="amount negative"><strong>${fmt(totalCategorySpend)}</strong></td>
          <td class="amount">100%</td>
          <td class="amount muted">${fmt(totalCategorySpend * (365 / 30))}</td>
        </tr>
      </tfoot>
    </table>
  </section>

  <!-- =============== TOP EXPENSES =============== -->
  <section class="page">
    <h2 class="section">Top expenses — last 31 days</h2>
    <p class="section-lede">Largest single transactions. Ask yourself: was each of these deliberate?</p>
    <table>
      <thead>
        <tr><th>Date</th><th>Payee</th><th>Category</th><th class="amount">Amount</th></tr>
      </thead>
      <tbody>
        ${topExpenses
          .map(
            (t) => `<tr>
          <td>${new Date(t.date).toLocaleDateString('fr-FR')}</td>
          <td>${esc(t.payee)}</td>
          <td class="muted">${esc(t.categoryName ?? '—')}</td>
          <td class="amount negative">${fmt(t.amount)}</td>
        </tr>`,
          )
          .join('')}
      </tbody>
    </table>
  </section>

  <!-- =============== SUBSCRIPTIONS =============== -->
  ${subscriptions.length > 0 ? `
  <section class="page">
    <h2 class="section">Subscriptions detected</h2>
    <p class="section-lede">Charges that repeat on a consistent cadence. Each one is annualised so you can see what it really costs per year.</p>
    <table>
      <thead>
        <tr>
          <th>Payee</th>
          <th>Category</th>
          <th class="amount">Per charge</th>
          <th class="amount">Cadence</th>
          <th class="amount">Annual</th>
        </tr>
      </thead>
      <tbody>
        ${subscriptions
          .slice()
          .sort((a, b) => b.annualCost - a.annualCost)
          .map(
            (s) => `<tr>
          <td>${esc(s.payee)}</td>
          <td class="muted">${esc(s.categoryName ?? '—')}</td>
          <td class="amount negative">${fmt(s.amount)}</td>
          <td class="amount muted">${cadenceLabel(s.cadenceDays)}</td>
          <td class="amount negative"><strong>${fmt(s.annualCost)}</strong></td>
        </tr>`,
          )
          .join('')}
      </tbody>
      <tfoot>
        <tr>
          <td colspan="4"><strong>Total annualised</strong></td>
          <td class="amount negative"><strong>${fmt(subscriptions.reduce((s, x) => s + x.annualCost, 0))}</strong></td>
        </tr>
      </tfoot>
    </table>
  </section>
  ` : ''}

  <div class="footer">
    Generated by Florin on ${new Date().toLocaleDateString('fr-FR')} — florin.app
  </div>
</body>
</html>`

  return new NextResponse(html, {
    headers: { 'Content-Type': 'text/html; charset=utf-8' },
  })
}

// ============================================================
// CSS (print-safe, multi-page layout)
// ============================================================

const CSS = `
@page { size: A4; margin: 18mm 16mm; }
@media print {
  body { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
  .print-btn { display: none !important; }
  .page { page-break-before: always; page-break-after: auto; }
  .page:first-of-type { page-break-before: avoid; }
  table, tr, .kpi, .chart, .flag { page-break-inside: avoid; }
  h2.section, h3.subsection { page-break-after: avoid; }
}

* { margin: 0; padding: 0; box-sizing: border-box; }
html, body { background: white; }
body {
  font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Inter', system-ui, sans-serif;
  color: #0f172a;
  font-size: 11px;
  line-height: 1.5;
  padding: 2rem;
  max-width: 820px;
  margin: 0 auto;
}

.page { padding: 8px 0; }

h1 { font-size: 36px; font-weight: 800; letter-spacing: -1px; margin-bottom: 6px; }
h2.section {
  font-size: 18px;
  font-weight: 700;
  letter-spacing: -0.3px;
  margin: 4px 0 6px;
  padding-bottom: 6px;
  border-bottom: 2px solid #0f172a;
}
h3.subsection {
  font-size: 13px;
  font-weight: 600;
  margin: 18px 0 8px;
  color: #334155;
  text-transform: uppercase;
  letter-spacing: 0.4px;
}

.section-lede { color: #64748b; font-size: 11px; margin: 2px 0 12px; max-width: 65ch; }

/* --- Cover page --- */
.cover { display: flex; flex-direction: column; justify-content: center; min-height: 230mm; }
.cover-brand { font-size: 12px; text-transform: uppercase; letter-spacing: 4px; color: #6366f1; font-weight: 700; margin-bottom: 40px; }
.cover-month { font-size: 18px; color: #475569; margin-bottom: 32px; text-transform: capitalize; }
.cover-verdict {
  font-size: 15px;
  line-height: 1.6;
  color: #1e293b;
  border-left: 4px solid #6366f1;
  padding: 10px 16px;
  margin-bottom: 40px;
  background: #f8fafc;
  max-width: 60ch;
}
.cover-hero { display: grid; grid-template-columns: 1fr 1fr; gap: 24px; margin-bottom: 48px; }
.hero-kpi { border: 1px solid #e2e8f0; border-radius: 12px; padding: 20px; background: #f8fafc; }
.hero-label { font-size: 10px; text-transform: uppercase; letter-spacing: 0.8px; color: #64748b; font-weight: 600; }
.hero-value { font-size: 32px; font-weight: 800; font-variant-numeric: tabular-nums; margin-top: 6px; letter-spacing: -0.5px; }
.hero-sub { font-size: 11px; color: #64748b; margin-top: 4px; }
.cover-footer { font-size: 10px; color: #94a3b8; margin-top: auto; padding-top: 20px; border-top: 1px solid #e2e8f0; }

/* --- KPI grids --- */
.kpi-grid {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 10px;
  margin-bottom: 14px;
}
.kpi {
  background: #f8fafc;
  border: 1px solid #e2e8f0;
  border-radius: 8px;
  padding: 12px;
}
.kpi-label { font-size: 9px; text-transform: uppercase; letter-spacing: 0.6px; color: #64748b; font-weight: 600; }
.kpi-value {
  font-size: 20px;
  font-weight: 700;
  font-variant-numeric: tabular-nums;
  margin-top: 4px;
  letter-spacing: -0.3px;
}
.kpi-value.small { font-size: 14px; }
.kpi-sub { font-size: 10px; color: #64748b; margin-top: 3px; }

.positive { color: #047857; }
.negative { color: #b91c1c; }
.muted { color: #64748b; }

/* --- Tables --- */
table { width: 100%; border-collapse: collapse; margin: 10px 0; font-size: 11px; }
th {
  text-align: left;
  font-size: 9px;
  text-transform: uppercase;
  letter-spacing: 0.5px;
  color: #64748b;
  padding: 6px 8px;
  border-bottom: 2px solid #e2e8f0;
  font-weight: 700;
}
td { padding: 6px 8px; border-bottom: 1px solid #f1f5f9; }
td.amount, th.amount { text-align: right; font-variant-numeric: tabular-nums; font-weight: 500; }
tfoot td { border-top: 2px solid #e2e8f0; font-weight: 700; padding-top: 8px; }

/* --- Charts --- */
.chart { margin: 12px 0 16px; }
.chart svg { width: 100%; height: auto; display: block; }
.chart-legend { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 10px; font-size: 10px; }
.legend-chip { display: inline-flex; align-items: center; gap: 6px; padding: 3px 8px; border: 1px solid #e2e8f0; border-radius: 999px; background: #f8fafc; }
.legend-chip em { color: #64748b; font-style: normal; font-variant-numeric: tabular-nums; }
.legend-dot { width: 8px; height: 8px; border-radius: 999px; display: inline-block; }

/* --- Flags --- */
.flags { list-style: none; display: flex; flex-direction: column; gap: 8px; }
.flag {
  display: flex;
  gap: 10px;
  padding: 10px 12px;
  border: 1px solid #e2e8f0;
  border-radius: 8px;
  background: #f8fafc;
  font-size: 11px;
}
.flag strong { font-weight: 700; }
.flag-body { color: #475569; }
.flag-dot { width: 8px; height: 8px; border-radius: 999px; margin-top: 6px; flex-shrink: 0; background: #64748b; }
.flag-warn { border-color: #fcd34d; background: #fffbeb; }
.flag-warn .flag-dot { background: #f59e0b; }
.flag-alert { border-color: #fca5a5; background: #fef2f2; }
.flag-alert .flag-dot { background: #dc2626; }
.flag-good { border-color: #86efac; background: #f0fdf4; }
.flag-good .flag-dot { background: #059669; }

/* --- Footer & print button --- */
.footer { margin-top: 40px; padding-top: 12px; border-top: 1px solid #e2e8f0; color: #94a3b8; font-size: 10px; text-align: center; }
.print-btn {
  position: fixed;
  bottom: 20px;
  right: 20px;
  background: #6366f1;
  color: white;
  border: none;
  padding: 10px 20px;
  border-radius: 8px;
  font-size: 14px;
  cursor: pointer;
  box-shadow: 0 4px 12px rgba(99,102,241,.3);
  z-index: 10;
}
.print-btn:hover { background: #4f46e5; }
`

// ============================================================
// Chart helpers — inline SVG so they print identically in all browsers.
// ============================================================

const PALETTE = [
  '#6366f1',
  '#ec4899',
  '#10b981',
  '#f59e0b',
  '#3b82f6',
  '#8b5cf6',
  '#ef4444',
  '#14b8a6',
  '#f97316',
  '#a855f7',
]

interface ChartGeom {
  width: number
  height: number
  padLeft: number
  padRight: number
  padTop: number
  padBottom: number
}

const FLOW_GEOM: ChartGeom = { width: 760, height: 240, padLeft: 48, padRight: 16, padTop: 10, padBottom: 28 }
const NET_GEOM: ChartGeom = { width: 760, height: 220, padLeft: 48, padRight: 16, padTop: 10, padBottom: 28 }
const CAT_GEOM: ChartGeom = { width: 760, height: 260, padLeft: 48, padRight: 16, padTop: 10, padBottom: 32 }

/** Y-axis label formatter — "1.2k", "850", "1.5M". Compact for a tight gutter. */
function yAxisFmt(v: number): string {
  const abs = Math.abs(v)
  if (abs >= 1_000_000) return `${(v / 1_000_000).toFixed(1)}M`
  if (abs >= 1_000) return `${(v / 1_000).toFixed(0)}k`
  return Math.round(v).toString()
}

/** Generate ~4 evenly-spaced gridline values from 0..max (or min..max). */
function ticks(min: number, max: number, n = 4): number[] {
  if (min === max) return [min]
  const step = (max - min) / n
  return Array.from({ length: n + 1 }, (_, i) => min + step * i)
}

function renderFlowsChart(flows: readonly MonthlyFlow[]): string {
  if (flows.length === 0) return '<p class="muted">No data yet.</p>'
  const g = FLOW_GEOM
  const innerW = g.width - g.padLeft - g.padRight
  const innerH = g.height - g.padTop - g.padBottom
  const max = Math.max(...flows.map((f) => Math.max(f.income, f.expense)), 1)
  const minNet = Math.min(0, ...flows.map((f) => f.net))
  const yMax = max * 1.1
  const yMin = Math.min(0, minNet * 1.1)
  const range = yMax - yMin

  const bandW = innerW / flows.length
  const barW = Math.min(16, (bandW - 6) / 2)

  const y = (v: number) => g.padTop + innerH - ((v - yMin) / range) * innerH

  const gridTicks = ticks(yMin, yMax, 4)
  const gridLines = gridTicks
    .map(
      (t) => `<line x1="${g.padLeft}" x2="${g.width - g.padRight}" y1="${y(t)}" y2="${y(t)}" stroke="#e2e8f0" stroke-width="1" />
      <text x="${g.padLeft - 4}" y="${y(t) + 3}" font-size="9" fill="#94a3b8" text-anchor="end">${yAxisFmt(t)}</text>`,
    )
    .join('')

  const bars = flows
    .map((f, i) => {
      const cx = g.padLeft + bandW * (i + 0.5)
      const y0 = y(0)
      const yi = y(f.income)
      const ye = y(f.expense)
      const label = formatMonthShort(f.month)
      return `
      <rect x="${cx - barW - 1}" y="${Math.min(yi, y0)}" width="${barW}" height="${Math.abs(y0 - yi)}" fill="#10b981" rx="2" />
      <rect x="${cx + 1}" y="${Math.min(ye, y0)}" width="${barW}" height="${Math.abs(y0 - ye)}" fill="#ef4444" rx="2" />
      <text x="${cx}" y="${g.height - g.padBottom + 14}" font-size="9" fill="#64748b" text-anchor="middle">${esc(label)}</text>`
    })
    .join('')

  const netPath = flows
    .map((f, i) => {
      const cx = g.padLeft + bandW * (i + 0.5)
      return `${i === 0 ? 'M' : 'L'} ${cx.toFixed(1)} ${y(f.net).toFixed(1)}`
    })
    .join(' ')

  const zeroLine =
    yMin < 0
      ? `<line x1="${g.padLeft}" x2="${g.width - g.padRight}" y1="${y(0)}" y2="${y(0)}" stroke="#94a3b8" stroke-width="1" stroke-dasharray="3 2" />`
      : ''

  return `<svg viewBox="0 0 ${g.width} ${g.height}" xmlns="http://www.w3.org/2000/svg">
    ${gridLines}
    ${zeroLine}
    ${bars}
    <path d="${netPath}" fill="none" stroke="#0f172a" stroke-width="2" />
  </svg>`
}

function renderNetWorthChart(series: readonly NetWorthPoint[]): string {
  if (series.length < 2) return '<p class="muted">Need at least two months of history to show a trend.</p>'
  const g = NET_GEOM
  const innerW = g.width - g.padLeft - g.padRight
  const innerH = g.height - g.padTop - g.padBottom
  const values = series.map((p) => p.cumulative)
  const max = Math.max(...values)
  const min = Math.min(...values)
  const pad = (max - min) * 0.1 || 1
  const yMax = max + pad
  const yMin = min - pad
  const range = yMax - yMin

  const x = (i: number) => g.padLeft + (i / (series.length - 1)) * innerW
  const y = (v: number) => g.padTop + innerH - ((v - yMin) / range) * innerH

  const gridTicks = ticks(yMin, yMax, 4)
  const gridLines = gridTicks
    .map(
      (t) => `<line x1="${g.padLeft}" x2="${g.width - g.padRight}" y1="${y(t)}" y2="${y(t)}" stroke="#e2e8f0" stroke-width="1" />
      <text x="${g.padLeft - 4}" y="${y(t) + 3}" font-size="9" fill="#94a3b8" text-anchor="end">${yAxisFmt(t)}</text>`,
    )
    .join('')

  const path = series.map((p, i) => `${i === 0 ? 'M' : 'L'} ${x(i).toFixed(1)} ${y(p.cumulative).toFixed(1)}`).join(' ')
  const fillPath = `${path} L ${x(series.length - 1).toFixed(1)} ${y(yMin).toFixed(1)} L ${x(0).toFixed(1)} ${y(yMin).toFixed(1)} Z`

  // Label every ~3rd month to keep the axis readable.
  const labelEvery = Math.max(1, Math.ceil(series.length / 8))
  const xLabels = series
    .map((p, i) => {
      if (i % labelEvery !== 0 && i !== series.length - 1) return ''
      return `<text x="${x(i)}" y="${g.height - g.padBottom + 14}" font-size="9" fill="#64748b" text-anchor="middle">${esc(formatMonthShort(p.month))}</text>`
    })
    .join('')

  return `<svg viewBox="0 0 ${g.width} ${g.height}" xmlns="http://www.w3.org/2000/svg">
    ${gridLines}
    <path d="${fillPath}" fill="#6366f1" fill-opacity="0.12" />
    <path d="${path}" fill="none" stroke="#6366f1" stroke-width="2.5" />
    ${xLabels}
  </svg>`
}

function renderCategoryTrendsChart(data: CategorySpendingSeries, topN: number): string {
  if (data.months.length < 2 || data.categories.length === 0) {
    return '<p class="muted">Not enough history to chart trends.</p>'
  }
  const g = CAT_GEOM
  const innerW = g.width - g.padLeft - g.padRight
  const innerH = g.height - g.padTop - g.padBottom
  const cats = data.categories.slice(0, topN)
  const max = Math.max(
    ...cats.flatMap((c) => c.monthly),
    1,
  )
  const yMax = max * 1.1
  const yMin = 0
  const range = yMax - yMin

  const x = (i: number) => g.padLeft + (i / (data.months.length - 1)) * innerW
  const y = (v: number) => g.padTop + innerH - ((v - yMin) / range) * innerH

  const gridTicks = ticks(yMin, yMax, 4)
  const gridLines = gridTicks
    .map(
      (t) => `<line x1="${g.padLeft}" x2="${g.width - g.padRight}" y1="${y(t)}" y2="${y(t)}" stroke="#e2e8f0" stroke-width="1" />
      <text x="${g.padLeft - 4}" y="${y(t) + 3}" font-size="9" fill="#94a3b8" text-anchor="end">${yAxisFmt(t)}</text>`,
    )
    .join('')

  const lines = cats
    .map((c, i) => {
      const stroke = PALETTE[i % PALETTE.length]
      const path = c.monthly
        .map((v, j) => `${j === 0 ? 'M' : 'L'} ${x(j).toFixed(1)} ${y(v).toFixed(1)}`)
        .join(' ')
      return `<path d="${path}" fill="none" stroke="${stroke}" stroke-width="1.6" stroke-linejoin="round" />`
    })
    .join('')

  const labelEvery = Math.max(1, Math.ceil(data.months.length / 8))
  const xLabels = data.months
    .map((m, i) => {
      if (i % labelEvery !== 0 && i !== data.months.length - 1) return ''
      return `<text x="${x(i)}" y="${g.height - g.padBottom + 14}" font-size="9" fill="#64748b" text-anchor="middle">${esc(formatMonthShort(m))}</text>`
    })
    .join('')

  return `<svg viewBox="0 0 ${g.width} ${g.height}" xmlns="http://www.w3.org/2000/svg">
    ${gridLines}
    ${lines}
    ${xLabels}
  </svg>`
}

// ============================================================
// Narrative helpers — tiny bits of inferred text on top of raw numbers.
// ============================================================

interface VerdictInput {
  net: number
  savingsPct: number | null
  last12SavingsPct: number | null
  overspentCategories: number
  subsAnnual: number
}

function buildVerdict(v: VerdictInput): string {
  const parts: string[] = []
  if (v.net >= 0 && (v.savingsPct ?? 0) >= 20) {
    parts.push(`Strong month — you saved ${v.savingsPct?.toFixed(0)}% of your income.`)
  } else if (v.net >= 0) {
    parts.push(`Net-positive month: you kept ${v.savingsPct === null ? 'some' : `${v.savingsPct.toFixed(0)}%`} of your income.`)
  } else {
    parts.push(`You spent more than you earned this month — negative net of ${fmt(Math.abs(v.net))}.`)
  }
  if (v.last12SavingsPct !== null) {
    parts.push(`Over the last 12 months your savings rate is ${v.last12SavingsPct >= 0 ? '+' : ''}${v.last12SavingsPct.toFixed(0)}%.`)
  }
  if (v.subsAnnual > 600) {
    parts.push(`Detected subscriptions run to ${fmt(v.subsAnnual)} per year — worth a review.`)
  }
  return parts.join(' ')
}

function buildNetWorthNarrative(series: readonly NetWorthPoint[]): string {
  if (series.length < 2) return ''
  const first = series[0]!
  const last = series[series.length - 1]!
  const delta = last.cumulative - first.cumulative
  const pct = first.cumulative !== 0 ? (delta / Math.abs(first.cumulative)) * 100 : null
  const monthly = delta / (series.length - 1)
  const direction = delta >= 0 ? 'up' : 'down'
  return `<p class="section-lede">Net worth is ${direction} <strong>${fmt(Math.abs(delta))}</strong>${
    pct !== null ? ` (${pct >= 0 ? '+' : ''}${pct.toFixed(0)}%)` : ''
  } since ${esc(formatMonthLong(first.month))} — averaging <strong>${fmt(Math.abs(monthly))}</strong> ${direction === 'up' ? 'gain' : 'loss'} per month.</p>`
}

interface Flag {
  severity: 'good' | 'warn' | 'alert'
  title: string
  body: string
}

interface FlagInput {
  categoryTrends: CategorySpendingSeries
  subscriptions: Awaited<ReturnType<typeof queries.getSubscriptions>>
  savingsRates: Awaited<ReturnType<typeof queries.getSavingsRates>>
  last12SavingsPct: number | null
}

function buildFlags(input: FlagInput): Flag[] {
  const flags: Flag[] = []

  // Categories where recent-half spend outpaced older-half by ≥30%.
  for (const cat of input.categoryTrends.categories.slice(0, 12)) {
    if (cat.monthly.length < 4) continue
    const mid = Math.floor(cat.monthly.length / 2)
    const older = cat.monthly.slice(0, mid)
    const recent = cat.monthly.slice(mid)
    const olderAvg = older.reduce((s, v) => s + v, 0) / Math.max(1, older.length)
    const recentAvg = recent.reduce((s, v) => s + v, 0) / Math.max(1, recent.length)
    if (olderAvg < 30) continue // noise floor
    const pct = ((recentAvg - olderAvg) / olderAvg) * 100
    if (pct >= 30 && recentAvg > olderAvg + 20) {
      flags.push({
        severity: 'warn',
        title: `${cat.emoji ? cat.emoji + ' ' : ''}${cat.categoryName} is trending up`,
        body: `Recent months average ${fmt(recentAvg)} vs. ${fmt(olderAvg)} earlier in the window (+${pct.toFixed(0)}%).`,
      })
    } else if (pct <= -25 && olderAvg > recentAvg + 20) {
      flags.push({
        severity: 'good',
        title: `${cat.emoji ? cat.emoji + ' ' : ''}${cat.categoryName} is cooling off`,
        body: `Average has dropped from ${fmt(olderAvg)} to ${fmt(recentAvg)} (${pct.toFixed(0)}%). Keep it up.`,
      })
    }
    if (flags.length >= 3) break
  }

  // Expensive subscriptions.
  const bigSubs = input.subscriptions
    .slice()
    .sort((a, b) => b.annualCost - a.annualCost)
    .slice(0, 2)
    .filter((s) => s.annualCost >= 120)
  for (const s of bigSubs) {
    flags.push({
      severity: 'warn',
      title: `Subscription: ${s.payee}`,
      body: `${fmt(s.amount)} every ${cadenceLabel(s.cadenceDays)} — ${fmt(s.annualCost)}/year.`,
    })
  }

  // Savings-rate verdict.
  if (input.last12SavingsPct !== null) {
    if (input.last12SavingsPct < 0) {
      flags.push({
        severity: 'alert',
        title: 'You spent more than you earned (12-month)',
        body: `Rolling 12-month savings rate is ${input.last12SavingsPct.toFixed(0)}%. The next step is finding one category to cut 10% from.`,
      })
    } else if (input.last12SavingsPct >= 25) {
      flags.push({
        severity: 'good',
        title: 'Savings rate is strong',
        body: `You're keeping ${input.last12SavingsPct.toFixed(0)}% of income over the last 12 months — well above most retirement planners' 15% target.`,
      })
    }
  }

  // Savings trend across 3/6/12.
  const { threeMonth, sixMonth, twelveMonth } = input.savingsRates
  if (threeMonth !== null && twelveMonth !== null && threeMonth + 8 < twelveMonth) {
    flags.push({
      severity: 'warn',
      title: 'Savings rate is slipping lately',
      body: `Last 3 months: ${threeMonth.toFixed(0)}%. Last 12 months: ${twelveMonth.toFixed(0)}%. Something changed in your recent spending.`,
    })
  } else if (threeMonth !== null && sixMonth !== null && threeMonth > sixMonth + 8) {
    flags.push({
      severity: 'good',
      title: 'Savings rate is accelerating',
      body: `Last 3 months: ${threeMonth.toFixed(0)}% — up from ${sixMonth.toFixed(0)}% over 6 months. Keep the pressure on.`,
    })
  }

  return flags
}

// ============================================================
// Formatting helpers
// ============================================================

function fmt(amount: number): string {
  return new Intl.NumberFormat('fr-FR', {
    style: 'currency',
    currency: 'EUR',
    minimumFractionDigits: 0,
    maximumFractionDigits: 0,
  }).format(amount)
}

function pctCell(v: number | null): string {
  if (v === null) return '<span class="muted">—</span>'
  const cls = v >= 0 ? 'positive' : 'negative'
  return `<span class="${cls}">${v >= 0 ? '+' : ''}${v.toFixed(0)}%</span>`
}

function formatMonthShort(key: string): string {
  const [y, m] = key.split('-')
  if (!y || !m) return key
  return new Date(Number(y), Number(m) - 1, 1).toLocaleDateString('fr-FR', {
    month: 'short',
  })
}

function formatMonthLong(key: string): string {
  const [y, m] = key.split('-')
  if (!y || !m) return key
  return new Date(Number(y), Number(m) - 1, 1).toLocaleDateString('fr-FR', {
    month: 'long',
    year: 'numeric',
  })
}

function cadenceLabel(days: number): string {
  if (days >= 27 && days <= 33) return 'month'
  if (days >= 6 && days <= 8) return 'week'
  if (days >= 13 && days <= 16) return '2 weeks'
  if (days >= 85 && days <= 95) return 'quarter'
  if (days >= 355 && days <= 375) return 'year'
  return `${days} d`
}

function esc(str: string): string {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
}
