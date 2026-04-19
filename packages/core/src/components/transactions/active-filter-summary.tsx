import { formatCurrencySigned } from '../../lib/format/currency'

export interface ActiveFilterSummaryProps {
  totalCount: number
  pageTotal: number | null
  direction: 'all' | 'expense' | 'income'
  startLabel?: string | null
  endLabel?: string | null
  payeeSearch?: string | null
  accountName?: string | null
  categoryLabel?: string | null
  minAmount?: number | null
  maxAmount?: number | null
  excludeTransfers?: boolean
}

/**
 * Displays a compact summary bar of currently active filters on the
 * Transactions page: one prominent top line (count + page total) and a row
 * of pills below describing each active filter. Purely presentational —
 * clearing individual filters happens through the filter bar itself.
 */
export function ActiveFilterSummary({
  totalCount,
  pageTotal,
  direction,
  startLabel,
  endLabel,
  payeeSearch,
  accountName,
  categoryLabel,
  minAmount,
  maxAmount,
  excludeTransfers,
}: ActiveFilterSummaryProps) {
  const pills: Array<{ key: string; label: string; tone?: 'expense' | 'income' | 'neutral' }> = []

  if (direction === 'expense') pills.push({ key: 'dir', label: 'Expenses only', tone: 'expense' })
  if (direction === 'income') pills.push({ key: 'dir', label: 'Income only', tone: 'income' })
  if (payeeSearch) pills.push({ key: 'q', label: `"${payeeSearch}"` })
  if (accountName) pills.push({ key: 'acct', label: accountName })
  if (categoryLabel) pills.push({ key: 'cat', label: categoryLabel })
  if (startLabel || endLabel) {
    const range =
      startLabel && endLabel
        ? `${startLabel} → ${endLabel}`
        : startLabel
          ? `from ${startLabel}`
          : `until ${endLabel}`
    pills.push({ key: 'range', label: range })
  }
  if (typeof minAmount === 'number' && typeof maxAmount === 'number') {
    pills.push({ key: 'amt', label: `${minAmount} € … ${maxAmount} €` })
  } else if (typeof minAmount === 'number') {
    pills.push({ key: 'amt', label: `≥ ${minAmount} €` })
  } else if (typeof maxAmount === 'number') {
    pills.push({ key: 'amt', label: `≤ ${maxAmount} €` })
  }
  if (excludeTransfers) pills.push({ key: 'xfer', label: 'No transfers' })

  return (
    <div className="flex flex-col gap-2 rounded-md border border-border/60 bg-muted/30 px-3 py-2 text-xs text-muted-foreground sm:flex-row sm:items-center sm:justify-between">
      <div className="flex items-baseline gap-2">
        <span className="text-[10px] font-semibold uppercase tracking-wide">Match</span>
        <span className="tabular-nums text-base font-semibold text-foreground">
          {totalCount.toLocaleString('fr-FR')}
        </span>
        <span>tx</span>
        {pageTotal !== null && (
          <>
            <span className="mx-1 text-border">·</span>
            <span className="text-[10px] uppercase tracking-wide">Page total</span>
            <span
              className={`tabular-nums text-sm font-semibold ${
                pageTotal < 0 ? 'text-destructive' : 'text-emerald-600 dark:text-emerald-400'
              }`}
            >
              {formatCurrencySigned(pageTotal)}
            </span>
          </>
        )}
      </div>
      {pills.length > 0 && (
        <div className="flex flex-wrap items-center gap-1.5">
          {pills.map((p) => (
            <span key={p.key} className={pillClassName(p.tone)}>
              {p.label}
            </span>
          ))}
        </div>
      )}
    </div>
  )
}

function pillClassName(tone?: 'expense' | 'income' | 'neutral'): string {
  const base = 'rounded-full border px-2 py-0.5 text-[11px] font-medium'
  if (tone === 'expense') {
    return `${base} border-destructive/40 bg-destructive/10 text-destructive`
  }
  if (tone === 'income') {
    return `${base} border-emerald-500/40 bg-emerald-500/10 text-emerald-700 dark:text-emerald-300`
  }
  return `${base} border-border bg-background text-foreground`
}
