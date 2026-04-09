'use client'

import { useMemo, useState, useTransition } from 'react'
import {
  Area,
  AreaChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { NoSSR } from '@/components/ui/no-ssr'
import { formatCurrency } from '@/lib/format/currency'
import {
  buildSchedule,
  compareSchedules,
  type LoanInputs,
  simulateSchedule,
} from '@/lib/loan/amortization'
import { updateLoanSettings } from '@/server/actions/accounts'
import { setCategoryLoanLink } from '@/server/actions/categories'

export interface LoanDetailsInitial {
  id: string
  currentBalance: string | number
  loanOriginalPrincipal: string | number | null
  loanInterestRate: string | number | null
  loanStartDate: Date | string | null
  loanTermMonths: number | null
  loanMonthlyPayment: string | number | null
}

export interface LinkedCategoryOption {
  id: string
  name: string
  emoji: string | null
  groupName: string
  /** The loan account id this category is currently linked to, if any. */
  linkedLoanAccountId: string | null
}

interface LoanDetailsCardProps {
  account: LoanDetailsInitial
  categories: ReadonlyArray<LinkedCategoryOption>
}

function toNumberOrNull(v: string | number | null | undefined): number | null {
  if (v === null || v === undefined || v === '') return null
  const n = Number(v)
  return Number.isFinite(n) ? n : null
}

function toDateOrNull(v: Date | string | null | undefined): Date | null {
  if (!v) return null
  const d = v instanceof Date ? v : new Date(v)
  return Number.isNaN(d.getTime()) ? null : d
}

function dateToInputValue(d: Date | null): string {
  if (!d) return ''
  return d.toISOString().slice(0, 10)
}

const dateFormatter = new Intl.DateTimeFormat('fr-FR', {
  month: 'short',
  year: 'numeric',
})

/**
 * Loan-kind-only detail card. Rendered on the account detail page when
 * `account.kind === 'loan'`. It does four things in one card:
 *
 *   1. Inline form for the loan parameters (principal, rate, term, etc.)
 *   2. Summary tiles: mensualité, taux, restant dû, mois restants
 *   3. Early-repayment simulator (lump sum + monthly extra) with a live
 *      side-by-side "what you save" summary
 *   4. Remaining-balance area chart + collapsible amortization schedule
 *
 * Everything is client-side re-computation from the same pure helpers in
 * `src/lib/loan/amortization.ts` — the server only owns the raw fields.
 */
export function LoanDetailsCard({ account, categories }: LoanDetailsCardProps) {
  const [pending, startTransition] = useTransition()
  const [saveError, setSaveError] = useState<string | null>(null)
  const [savedAt, setSavedAt] = useState<number | null>(null)

  // Categories already linked to THIS loan account (there can be many — e.g.
  // one "Student loans" category and one "Student loans extra" category).
  const linkedCategoryIds = useMemo(
    () =>
      categories.filter((c) => c.linkedLoanAccountId === account.id).map((c) => c.id),
    [categories, account.id],
  )
  // The picker lets the user add one more link at a time. Seed it blank so
  // selecting a category explicitly is a deliberate action.
  const [categoryToLink, setCategoryToLink] = useState('')
  const [linkPending, startLinkTransition] = useTransition()
  const [linkStatus, setLinkStatus] = useState<string | null>(null)
  const [linkError, setLinkError] = useState<string | null>(null)

  // Form state is seeded from the account row. Interest rate is stored as a
  // decimal (0.035) but shown in percent (3.5) — less surprising to type.
  const [principal, setPrincipal] = useState(() =>
    toNumberOrNull(account.loanOriginalPrincipal)?.toString() ?? '',
  )
  const [ratePercent, setRatePercent] = useState(() => {
    const r = toNumberOrNull(account.loanInterestRate)
    return r === null ? '' : (r * 100).toString()
  })
  const [startDate, setStartDate] = useState(() =>
    dateToInputValue(toDateOrNull(account.loanStartDate)),
  )
  const [termMonths, setTermMonths] = useState(() => account.loanTermMonths?.toString() ?? '')
  const [monthlyPayment, setMonthlyPayment] = useState(() =>
    toNumberOrNull(account.loanMonthlyPayment)?.toString() ?? '',
  )

  // Simulator state — start both knobs at 0 (no extra payments) so the
  // comparison matches the base schedule exactly on first render.
  const [extraMonthly, setExtraMonthly] = useState('0')
  const [lumpSumAmount, setLumpSumAmount] = useState('0')
  const [lumpSumMonth, setLumpSumMonth] = useState('1')

  const [showSchedule, setShowSchedule] = useState(false)

  // Parse the form fields into the canonical loan-input object. Returns
  // null when any required field is missing — the rest of the render path
  // then knows to prompt the user to fill the form instead of drawing an
  // empty chart.
  const loanInputs = useMemo((): LoanInputs | null => {
    const p = Number(principal)
    const r = Number(ratePercent) / 100
    const n = Number(termMonths)
    const s = startDate ? new Date(`${startDate}T00:00:00Z`) : null
    if (
      !Number.isFinite(p) ||
      p <= 0 ||
      !Number.isFinite(r) ||
      r < 0 ||
      !Number.isFinite(n) ||
      n <= 0 ||
      !s ||
      Number.isNaN(s.getTime())
    ) {
      return null
    }
    return { originalPrincipal: p, annualRate: r, termMonths: n, startDate: s }
  }, [principal, ratePercent, termMonths, startDate])

  const base = useMemo(() => (loanInputs ? buildSchedule(loanInputs) : null), [loanInputs])

  // Let the user override the computed mensualité (banks sometimes round
  // differently, or the loan contract has a non-standard payment). When
  // they've entered one, use it as the base payment for both base and
  // simulated schedules; otherwise fall back to the OLS-derived value.
  const baseMonthlyPayment = useMemo(() => {
    const m = Number(monthlyPayment)
    if (Number.isFinite(m) && m > 0) return m
    return base?.summary.monthlyPayment ?? 0
  }, [monthlyPayment, base?.summary.monthlyPayment])

  const effectiveBase = useMemo(() => {
    if (!loanInputs) return null
    return simulateSchedule(loanInputs, { baseMonthlyPayment })
  }, [loanInputs, baseMonthlyPayment])

  // Simulator: stack the monthly extra table with the optional lump sum.
  const simulated = useMemo(() => {
    if (!loanInputs) return null
    const extraMonthlyNum = Math.max(0, Number(extraMonthly) || 0)
    const extraTable: Record<number, number> = {}
    if (extraMonthlyNum > 0) {
      for (let i = 1; i <= loanInputs.termMonths * 2; i++) {
        extraTable[i] = extraMonthlyNum
      }
    }
    return simulateSchedule(loanInputs, {
      baseMonthlyPayment,
      extraPayments: extraTable,
      lumpSumAmount: Math.max(0, Number(lumpSumAmount) || 0),
      lumpSumMonth: Math.max(1, Number(lumpSumMonth) || 1),
    })
  }, [loanInputs, baseMonthlyPayment, extraMonthly, lumpSumAmount, lumpSumMonth])

  const comparison = useMemo(() => {
    if (!effectiveBase || !simulated) return null
    return compareSchedules(effectiveBase, simulated)
  }, [effectiveBase, simulated])

  // Dataset for the remaining-balance chart. Two series overlaid: the base
  // schedule ("what the contract says") and the simulated one ("what you
  // could do with extra payments"). Keyed by month index so the X-axis
  // stays monotonically increasing even when simulated ends earlier.
  const chartData = useMemo(() => {
    if (!effectiveBase) return []
    const byIndex = new Map<number, { index: number; base: number; simulated?: number; date: number }>()
    for (const row of effectiveBase.rows) {
      byIndex.set(row.index, {
        index: row.index,
        date: row.date.getTime(),
        base: row.balanceAfter,
      })
    }
    if (simulated) {
      for (const row of simulated.rows) {
        const existing = byIndex.get(row.index) ?? {
          index: row.index,
          date: row.date.getTime(),
          base: 0,
        }
        existing.simulated = row.balanceAfter
        byIndex.set(row.index, existing)
      }
    }
    return Array.from(byIndex.values()).sort((a, b) => a.index - b.index)
  }, [effectiveBase, simulated])

  const onLinkCategory = (catId: string) => {
    if (!catId) return
    setLinkError(null)
    setLinkStatus(null)
    startLinkTransition(async () => {
      const result = await setCategoryLoanLink({
        categoryId: catId,
        loanAccountId: account.id,
      })
      if (!result.success) {
        setLinkError(result.error ?? 'Failed to link')
        return
      }
      setLinkStatus(`Linked · ${result.data?.touched ?? 0} past payment(s) applied to loan.`)
      setCategoryToLink('')
    })
  }

  const onUnlinkCategory = (catId: string) => {
    setLinkError(null)
    setLinkStatus(null)
    startLinkTransition(async () => {
      const result = await setCategoryLoanLink({
        categoryId: catId,
        loanAccountId: null,
      })
      if (!result.success) {
        setLinkError(result.error ?? 'Failed to unlink')
        return
      }
      setLinkStatus(`Unlinked · ${result.data?.touched ?? 0} mirror(s) removed.`)
    })
  }

  const onSave = () => {
    setSaveError(null)
    setSavedAt(null)
    startTransition(async () => {
      const result = await updateLoanSettings({
        id: account.id,
        loanOriginalPrincipal: principal === '' ? null : Number(principal),
        loanInterestRatePercent: ratePercent === '' ? null : Number(ratePercent),
        loanStartDate: startDate === '' ? null : startDate,
        loanTermMonths: termMonths === '' ? null : Number(termMonths),
        loanMonthlyPayment: monthlyPayment === '' ? null : Number(monthlyPayment),
      })
      if (!result.success) {
        setSaveError(result.error ?? 'Failed to save')
        return
      }
      setSavedAt(Date.now())
    })
  }

  const currentBalance = Number(account.currentBalance)
  // "Months remaining at the base mensualité" — derived from the simulated
  // base schedule rather than (termMonths - months since start) so partial
  // prepayments in real life show up as a shorter projected tail.
  const remainingMonths = effectiveBase?.summary.months ?? null

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base">Loan details</CardTitle>
      </CardHeader>
      <CardContent className="space-y-6">
        {/* ============================== form ============================== */}
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          <div className="space-y-1">
            <Label htmlFor="loan-principal">Original principal (EUR)</Label>
            <Input
              id="loan-principal"
              type="number"
              step="0.01"
              min="0"
              value={principal}
              onChange={(e) => setPrincipal(e.target.value)}
              placeholder="e.g. 35000"
            />
          </div>
          <div className="space-y-1">
            <Label htmlFor="loan-rate">Annual rate (%)</Label>
            <Input
              id="loan-rate"
              type="number"
              step="0.001"
              min="0"
              value={ratePercent}
              onChange={(e) => setRatePercent(e.target.value)}
              placeholder="e.g. 3.5"
            />
          </div>
          <div className="space-y-1">
            <Label htmlFor="loan-term">Term (months)</Label>
            <Input
              id="loan-term"
              type="number"
              step="1"
              min="1"
              value={termMonths}
              onChange={(e) => setTermMonths(e.target.value)}
              placeholder="e.g. 240"
            />
          </div>
          <div className="space-y-1">
            <Label htmlFor="loan-start">Start date</Label>
            <Input
              id="loan-start"
              type="date"
              value={startDate}
              onChange={(e) => setStartDate(e.target.value)}
            />
          </div>
          <div className="space-y-1">
            <Label htmlFor="loan-monthly">Monthly payment (EUR)</Label>
            <Input
              id="loan-monthly"
              type="number"
              step="0.01"
              min="0"
              value={monthlyPayment}
              onChange={(e) => setMonthlyPayment(e.target.value)}
              placeholder="optional — computed if blank"
            />
          </div>
          <div className="flex items-end">
            <Button type="button" onClick={onSave} disabled={pending} className="w-full">
              {pending ? 'Saving…' : 'Save loan settings'}
            </Button>
          </div>
        </div>
        {saveError && <p className="text-xs text-destructive">{saveError}</p>}
        {savedAt && !saveError && (
          <p className="text-xs text-emerald-600">Saved · loan details updated.</p>
        )}

        {/* ============================ linked categories ============== */}
        {/* Rendered unconditionally (not gated on loan params) so the user
            can wire up the category→loan link even before filling in the
            amortization details. */}
        <div className="space-y-2 rounded-lg border border-border/60 bg-muted/20 p-3">
          <h3 className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
            Catégories liées à ce prêt
          </h3>
          <p className="text-[11px] text-muted-foreground">
            Les transactions catégorisées dans une catégorie liée mettent automatiquement à jour
            le solde de ce prêt (comme un "tracking account" YNAB).
          </p>
          {linkedCategoryIds.length > 0 && (
            <ul className="flex flex-wrap gap-1.5">
              {linkedCategoryIds.map((id) => {
                const cat = categories.find((c) => c.id === id)
                if (!cat) return null
                return (
                  <li
                    key={id}
                    className="inline-flex items-center gap-1 rounded-full border border-emerald-500/40 bg-emerald-500/10 px-2 py-0.5 text-[11px] text-emerald-700 dark:text-emerald-300"
                  >
                    {cat.emoji && <span aria-hidden>{cat.emoji}</span>}
                    <span className="font-medium">{cat.name}</span>
                    <span className="text-muted-foreground">· {cat.groupName}</span>
                    <button
                      type="button"
                      onClick={() => onUnlinkCategory(id)}
                      disabled={linkPending}
                      className="ml-0.5 text-muted-foreground hover:text-destructive"
                      title="Unlink this category from the loan"
                      aria-label={`Unlink ${cat.name}`}
                    >
                      ×
                    </button>
                  </li>
                )
              })}
            </ul>
          )}
          <div className="flex items-center gap-2">
            <select
              value={categoryToLink}
              onChange={(e) => setCategoryToLink(e.target.value)}
              disabled={linkPending}
              className="h-8 flex-1 rounded-md border border-border bg-background px-2 text-xs"
              aria-label="Link a category to this loan"
            >
              <option value="">Link a category…</option>
              {categories
                .filter((c) => c.linkedLoanAccountId !== account.id)
                .map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.groupName} · {c.name}
                    {c.linkedLoanAccountId ? ' (already linked elsewhere)' : ''}
                  </option>
                ))}
            </select>
            <Button
              type="button"
              variant="outline"
              size="sm"
              disabled={linkPending || !categoryToLink}
              onClick={() => onLinkCategory(categoryToLink)}
            >
              {linkPending ? '…' : 'Link'}
            </Button>
          </div>
          {linkError && <p className="text-xs text-destructive">{linkError}</p>}
          {linkStatus && !linkError && (
            <p className="text-xs text-emerald-600">{linkStatus}</p>
          )}
        </div>

        {/* ============================== summary ========================== */}
        {loanInputs && effectiveBase ? (
          <>
            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
              <Tile label="Encours" value={formatCurrency(currentBalance)} />
              <Tile label="Mensualité" value={formatCurrency(effectiveBase.summary.monthlyPayment)} />
              <Tile
                label="Mois restants"
                value={remainingMonths !== null ? `${remainingMonths} mois` : '—'}
              />
              <Tile
                label="Intérêts restants"
                value={formatCurrency(effectiveBase.summary.totalInterest)}
              />
            </div>

            {/* ============================ simulator ======================= */}
            <div className="space-y-3 rounded-lg border border-border/60 bg-muted/20 p-3">
              <div className="flex items-center justify-between">
                <h3 className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                  Simulateur de remboursement anticipé
                </h3>
              </div>
              <div className="grid gap-3 sm:grid-cols-3">
                <div className="space-y-1">
                  <Label htmlFor="sim-extra-monthly" className="text-[11px]">
                    Extra mensuel (EUR)
                  </Label>
                  <Input
                    id="sim-extra-monthly"
                    type="number"
                    step="10"
                    min="0"
                    value={extraMonthly}
                    onChange={(e) => setExtraMonthly(e.target.value)}
                  />
                </div>
                <div className="space-y-1">
                  <Label htmlFor="sim-lump" className="text-[11px]">
                    Remboursement unique (EUR)
                  </Label>
                  <Input
                    id="sim-lump"
                    type="number"
                    step="100"
                    min="0"
                    value={lumpSumAmount}
                    onChange={(e) => setLumpSumAmount(e.target.value)}
                  />
                </div>
                <div className="space-y-1">
                  <Label htmlFor="sim-lump-month" className="text-[11px]">
                    Appliqué au mois n°
                  </Label>
                  <Input
                    id="sim-lump-month"
                    type="number"
                    step="1"
                    min="1"
                    value={lumpSumMonth}
                    onChange={(e) => setLumpSumMonth(e.target.value)}
                  />
                </div>
              </div>
              {comparison && (
                <div className="grid gap-2 text-xs sm:grid-cols-3">
                  <ComparisonTile
                    label="Mois économisés"
                    value={`${comparison.monthsSaved} mois`}
                    highlight={comparison.monthsSaved > 0}
                  />
                  <ComparisonTile
                    label="Intérêts économisés"
                    value={formatCurrency(comparison.interestSaved)}
                    highlight={comparison.interestSaved > 0}
                  />
                  <ComparisonTile
                    label="Nouvelle fin"
                    value={dateFormatter.format(comparison.newEndDate)}
                    highlight={comparison.monthsSaved > 0}
                  />
                </div>
              )}
            </div>

            {/* ============================ chart =========================== */}
            <div>
              <h3 className="mb-2 text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                Encours dans le temps
              </h3>
              <div className="h-60">
                <NoSSR fallback={<div className="h-full w-full" />}>
                  <ResponsiveContainer width="100%" height="100%">
                    <AreaChart data={chartData} margin={{ top: 10, right: 16, left: 0, bottom: 0 }}>
                      <defs>
                        <linearGradient id="loanBase" x1="0" y1="0" x2="0" y2="1">
                          <stop offset="0%" stopColor="var(--chart-1)" stopOpacity={0.28} />
                          <stop offset="100%" stopColor="var(--chart-1)" stopOpacity={0} />
                        </linearGradient>
                        <linearGradient id="loanSim" x1="0" y1="0" x2="0" y2="1">
                          <stop offset="0%" stopColor="var(--chart-3)" stopOpacity={0.32} />
                          <stop offset="100%" stopColor="var(--chart-3)" stopOpacity={0} />
                        </linearGradient>
                      </defs>
                      <CartesianGrid strokeDasharray="3 3" stroke="var(--border)" />
                      <XAxis
                        dataKey="index"
                        stroke="var(--muted-foreground)"
                        tick={{ fontSize: 11, fill: 'var(--muted-foreground)' }}
                        axisLine={false}
                        tickLine={false}
                        tickFormatter={(v: number) => `m${v}`}
                      />
                      <YAxis
                        tickFormatter={(v: number) => `${(v / 1000).toFixed(0)}k`}
                        stroke="var(--muted-foreground)"
                        tick={{ fontSize: 11, fill: 'var(--muted-foreground)' }}
                        axisLine={false}
                        tickLine={false}
                        width={48}
                      />
                      <Tooltip
                        contentStyle={{
                          borderRadius: 10,
                          background: 'var(--popover)',
                          border: '1px solid var(--border)',
                          color: 'var(--popover-foreground)',
                          fontSize: 12,
                          padding: '8px 10px',
                          boxShadow: '0 6px 24px -12px rgb(0 0 0 / 0.25)',
                        }}
                        formatter={(value, name) => [
                          formatCurrency(Number(value)),
                          name === 'base' ? 'Base' : 'Simulated',
                        ]}
                        labelFormatter={(label) => `Mois ${label}`}
                      />
                      <Area
                        type="monotone"
                        dataKey="base"
                        stroke="var(--chart-1)"
                        strokeWidth={2}
                        fill="url(#loanBase)"
                        isAnimationActive={false}
                      />
                      <Area
                        type="monotone"
                        dataKey="simulated"
                        stroke="var(--chart-3)"
                        strokeWidth={2}
                        fill="url(#loanSim)"
                        isAnimationActive={false}
                      />
                    </AreaChart>
                  </ResponsiveContainer>
                </NoSSR>
              </div>
            </div>

            {/* ============================ schedule ======================== */}
            <div>
              <Button
                variant="ghost"
                size="sm"
                onClick={() => setShowSchedule((v) => !v)}
                className="h-7 px-2 text-[11px] font-medium text-muted-foreground hover:text-foreground"
              >
                {showSchedule ? 'Hide échéancier' : 'Show échéancier'}
              </Button>
              {showSchedule && (
                <div className="mt-2 max-h-80 overflow-y-auto rounded-md border border-border/60">
                  <table className="w-full text-xs">
                    <thead className="sticky top-0 bg-muted/50 text-[10px] uppercase tracking-wide text-muted-foreground">
                      <tr>
                        <th className="px-2 py-1 text-left">#</th>
                        <th className="px-2 py-1 text-left">Date</th>
                        <th className="px-2 py-1 text-right">Mensualité</th>
                        <th className="px-2 py-1 text-right">Intérêts</th>
                        <th className="px-2 py-1 text-right">Capital</th>
                        <th className="px-2 py-1 text-right">Extra</th>
                        <th className="px-2 py-1 text-right">Restant</th>
                      </tr>
                    </thead>
                    <tbody className="font-mono tabular-nums">
                      {simulated?.rows.map((row) => (
                        <tr key={row.index} className="odd:bg-muted/10">
                          <td className="px-2 py-1 text-left">{row.index}</td>
                          <td className="px-2 py-1 text-left">
                            {dateFormatter.format(row.date)}
                          </td>
                          <td className="px-2 py-1 text-right">{formatCurrency(row.payment)}</td>
                          <td className="px-2 py-1 text-right text-muted-foreground">
                            {formatCurrency(row.interest)}
                          </td>
                          <td className="px-2 py-1 text-right">{formatCurrency(row.principal)}</td>
                          <td className="px-2 py-1 text-right text-emerald-600">
                            {row.extraPayment > 0 ? formatCurrency(row.extraPayment) : '—'}
                          </td>
                          <td className="px-2 py-1 text-right">{formatCurrency(row.balanceAfter)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </div>
          </>
        ) : (
          <p className="text-xs text-muted-foreground">
            Fill in the loan parameters above (principal, rate, term, start date) to unlock the
            amortization schedule, simulator, and remaining-balance chart.
          </p>
        )}
      </CardContent>
    </Card>
  )
}

function Tile({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-md border border-border/60 bg-background p-3">
      <p className="text-[10px] uppercase tracking-wide text-muted-foreground">{label}</p>
      <p className="mt-0.5 text-lg font-semibold">{value}</p>
    </div>
  )
}

function ComparisonTile({
  label,
  value,
  highlight,
}: {
  label: string
  value: string
  highlight: boolean
}) {
  return (
    <div
      className={`rounded-md border p-2 ${
        highlight ? 'border-emerald-500/40 bg-emerald-500/10' : 'border-border/60 bg-background'
      }`}
    >
      <p className="text-[10px] uppercase tracking-wide text-muted-foreground">{label}</p>
      <p
        className={`mt-0.5 text-sm font-semibold ${highlight ? 'text-emerald-700 dark:text-emerald-300' : ''}`}
      >
        {value}
      </p>
    </div>
  )
}
