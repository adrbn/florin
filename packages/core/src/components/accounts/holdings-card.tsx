'use client'

import { useMemo, useState, useTransition } from 'react'
import { Button } from '../ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '../ui/card'
import { Input } from '../ui/input'
import { Label } from '../ui/label'
import { useT } from '../../i18n/context'
import { formatCurrency, formatCurrencySigned } from '../../lib/format/currency'
import type {
  ActionResult,
  AddHoldingInput,
  HoldingView,
  PortfolioValuation,
  UpdateHoldingInput,
} from '../../types/index'

interface HoldingsCardProps {
  accountId: string
  holdings: HoldingView[]
  valuation: PortfolioValuation
  locale: string
  onAddHolding: (input: AddHoldingInput) => Promise<ActionResult>
  onUpdateHolding: (id: string, input: UpdateHoldingInput) => Promise<ActionResult>
  onDeleteHolding: (id: string) => Promise<ActionResult>
  onRefreshPrices: () => Promise<ActionResult>
}

/** PEA contribution ceiling in EUR — the regulatory cap on versements. */
const PEA_CEILING = 150_000

/** A blank add-form draft. */
const EMPTY_DRAFT: HoldingDraft = {
  label: '',
  isin: '',
  quoteSymbol: '',
  quantity: '',
  costBasis: '',
  currency: 'EUR',
}

interface HoldingDraft {
  label: string
  isin: string
  quoteSymbol: string
  quantity: string
  costBasis: string
  currency: string
}

function holdingToDraft(h: HoldingView): HoldingDraft {
  return {
    label: h.label,
    isin: h.isin ?? '',
    quoteSymbol: h.quoteSymbol ?? '',
    quantity: String(h.quantity),
    costBasis: String(h.costBasis),
    currency: h.currency || 'EUR',
  }
}

/**
 * Validate + normalize a draft into an AddHoldingInput-shaped payload (minus
 * the accountId, which the caller attaches). Returns an error key string when
 * invalid so the caller can surface a translated message.
 */
function parseDraft(
  draft: HoldingDraft,
): { ok: true; value: Omit<AddHoldingInput, 'accountId'> } | { ok: false; error: string } {
  const label = draft.label.trim()
  if (!label) return { ok: false, error: 'labelRequired' }
  const quantity = Number(draft.quantity)
  if (!Number.isFinite(quantity) || quantity < 0) return { ok: false, error: 'quantityInvalid' }
  const costBasis = Number(draft.costBasis)
  if (!Number.isFinite(costBasis) || costBasis < 0) return { ok: false, error: 'costBasisInvalid' }
  return {
    ok: true,
    value: {
      label,
      isin: draft.isin.trim() || null,
      quoteSymbol: draft.quoteSymbol.trim() || null,
      quantity,
      costBasis,
      currency: draft.currency.trim() || 'EUR',
    },
  }
}

/**
 * Broker-portfolio detail card. Rendered on the account detail page when
 * `account.kind === 'broker_portfolio'`. Shows header KPIs (market value +
 * cash, plus-value latente, versé/marché split, a price-refresh button), a
 * per-holding table, an inline add/edit form, and per-row delete with confirm.
 *
 * Like {@link LoanDetailsCard} it receives every server action as a prop so
 * the component stays DB-agnostic and bindable from both web and desktop.
 */
export function HoldingsCard({
  accountId,
  holdings,
  valuation,
  locale,
  onAddHolding,
  onUpdateHolding,
  onDeleteHolding,
  onRefreshPrices,
}: HoldingsCardProps) {
  const t = useT()
  const [refreshPending, startRefresh] = useTransition()
  const [savePending, startSave] = useTransition()
  const [deletePending, startDelete] = useTransition()

  // Inline form state. `editingId === null` while adding a new holding; set to
  // a holding id while editing that row.
  const [showForm, setShowForm] = useState(false)
  const [editingId, setEditingId] = useState<string | null>(null)
  const [draft, setDraft] = useState<HoldingDraft>(EMPTY_DRAFT)
  const [formError, setFormError] = useState<string | null>(null)
  const [refreshError, setRefreshError] = useState<string | null>(null)
  const [deletingId, setDeletingId] = useState<string | null>(null)

  // Header value = invested holdings (marketValue) + idle cash in the wrapper.
  const totalValue = valuation.marketValue + valuation.cash
  const plusValuePct = useMemo(() => {
    if (valuation.costBasis <= 0) return null
    return (valuation.plusValue / valuation.costBasis) * 100
  }, [valuation.costBasis, valuation.plusValue])

  // Most recent price timestamp across all holdings, and whether any is stale.
  const lastPriceAt = useMemo(() => {
    let latest: number | null = null
    for (const h of holdings) {
      if (!h.lastPriceAt) continue
      const ts = Date.parse(h.lastPriceAt)
      if (Number.isNaN(ts)) continue
      if (latest === null || ts > latest) latest = ts
    }
    return latest
  }, [holdings])
  const anyStale = useMemo(() => holdings.some((h) => h.isStale), [holdings])

  const dateFormatter = useMemo(
    () => new Intl.DateTimeFormat(locale, { dateStyle: 'medium', timeStyle: 'short' }),
    [locale],
  )

  const onRefresh = () => {
    setRefreshError(null)
    startRefresh(async () => {
      const result = await onRefreshPrices()
      if (!result.success) {
        setRefreshError(result.error ?? t('common.error', 'Something went wrong'))
      }
    })
  }

  const openAddForm = () => {
    setEditingId(null)
    setDraft(EMPTY_DRAFT)
    setFormError(null)
    setShowForm(true)
  }

  const openEditForm = (h: HoldingView) => {
    setEditingId(h.id)
    setDraft(holdingToDraft(h))
    setFormError(null)
    setShowForm(true)
  }

  const closeForm = () => {
    setShowForm(false)
    setEditingId(null)
    setDraft(EMPTY_DRAFT)
    setFormError(null)
  }

  const errorMessageFor = (key: string): string => {
    switch (key) {
      case 'labelRequired':
        return t('holdings.label', 'Label')
      case 'quantityInvalid':
        return t('holdings.quantity', 'Quantity')
      case 'costBasisInvalid':
        return t('holdings.costBasis', 'Cost basis')
      default:
        return t('common.error', 'Invalid')
    }
  }

  const onSubmit = () => {
    const parsed = parseDraft(draft)
    if (!parsed.ok) {
      setFormError(errorMessageFor(parsed.error))
      return
    }
    setFormError(null)
    startSave(async () => {
      const result = editingId
        ? await onUpdateHolding(editingId, parsed.value)
        : await onAddHolding({ accountId, ...parsed.value })
      if (!result.success) {
        setFormError(result.error ?? t('common.error', 'Something went wrong'))
        return
      }
      closeForm()
    })
  }

  const onConfirmDelete = (id: string) => {
    startDelete(async () => {
      const result = await onDeleteHolding(id)
      if (!result.success) {
        setRefreshError(result.error ?? t('common.error', 'Something went wrong'))
      }
      setDeletingId(null)
    })
  }

  return (
    <Card>
      <CardHeader>
        <div className="flex flex-wrap items-center justify-between gap-2">
          <CardTitle className="text-base">{t('holdings.title', 'Holdings')}</CardTitle>
          <div className="flex flex-col items-end gap-0.5">
            <Button
              type="button"
              variant="outline"
              size="sm"
              onClick={onRefresh}
              disabled={refreshPending}
            >
              {refreshPending ? t('common.loading', 'Loading…') : t('holdings.refresh', 'Refresh prices')}
            </Button>
            {lastPriceAt !== null && (
              <p className="text-[10px] text-muted-foreground">
                {t(
                  'holdings.lastPrice',
                  { date: dateFormatter.format(new Date(lastPriceAt)) },
                  `Price as of ${dateFormatter.format(new Date(lastPriceAt))}`,
                )}
                {anyStale && (
                  <span className="ml-1 text-amber-600 dark:text-amber-400">
                    · {t('holdings.stale', 'Stale price')}
                  </span>
                )}
              </p>
            )}
          </div>
        </div>
        {valuation.verse > 0 && (
          <div className="mt-3 space-y-1">
            <div className="flex items-center justify-between gap-2 text-[11px] tabular-nums">
              <span className="text-muted-foreground">
                {t(
                  'holdings.peaCeiling',
                  { verse: formatCurrency(valuation.verse), ceiling: formatCurrency(PEA_CEILING) },
                  `Contributed ${formatCurrency(valuation.verse)} / ${formatCurrency(PEA_CEILING)} (PEA cap)`,
                )}
              </span>
              <span className="font-medium text-muted-foreground">
                {Math.min(100, (valuation.verse / PEA_CEILING) * 100).toFixed(0)}%
              </span>
            </div>
            <div className="h-1.5 w-full overflow-hidden rounded-full bg-muted">
              <div
                className="h-full rounded-full bg-primary"
                style={{
                  width: `${Math.min(100, Math.max(0, (valuation.verse / PEA_CEILING) * 100))}%`,
                }}
                aria-hidden="true"
              />
            </div>
            <p className="text-[10px] text-muted-foreground">
              {t('holdings.peaExemption', "Exonération d'impôt après 5 ans de détention")}
            </p>
          </div>
        )}
      </CardHeader>
      <CardContent className="space-y-5">
        {refreshError && <p className="text-xs text-destructive">{refreshError}</p>}

        {/* ============================== KPIs ============================== */}
        <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          <Kpi label={t('holdings.marketValue', 'Market value')} value={formatCurrency(totalValue)} />
          <Kpi
            label={t('holdings.plusValue', 'Unrealized gain')}
            value={formatCurrencySigned(valuation.plusValue)}
            tone={valuation.plusValue >= 0 ? 'positive' : 'negative'}
            sublabel={
              plusValuePct !== null
                ? `${plusValuePct >= 0 ? '+' : ''}${plusValuePct.toFixed(1)}%`
                : undefined
            }
          />
          <Kpi label={t('holdings.verse', 'Contributed')} value={formatCurrency(valuation.verse)} />
          <Kpi
            label={t('holdings.marche', 'Market')}
            value={formatCurrencySigned(valuation.marche)}
            tone={valuation.marche >= 0 ? 'positive' : 'negative'}
          />
        </div>
        {valuation.cash !== 0 && (
          <p className="text-[11px] text-muted-foreground">
            {t('holdings.cash', 'Cash')}: {formatCurrency(valuation.cash)}
          </p>
        )}

        {/* ============================== table ============================ */}
        {holdings.length === 0 ? (
          <p className="rounded-md border border-border/60 bg-muted/20 p-3 text-xs text-muted-foreground">
            {t('holdings.empty', 'No holdings yet. Add your first.')}
          </p>
        ) : (
          <div className="overflow-x-auto rounded-md border border-border/60">
            <table className="w-full text-xs">
              <thead className="bg-muted/50 text-[10px] uppercase tracking-wide text-muted-foreground">
                <tr>
                  <th className="px-2 py-1.5 text-left">{t('holdings.label', 'Label')}</th>
                  <th className="px-2 py-1.5 text-left">{t('holdings.isin', 'ISIN')}</th>
                  <th className="px-2 py-1.5 text-left">{t('holdings.symbol', 'Symbol')}</th>
                  <th className="px-2 py-1.5 text-right">{t('holdings.quantity', 'Quantity')}</th>
                  <th className="px-2 py-1.5 text-right">{t('holdings.price', 'Price')}</th>
                  <th className="px-2 py-1.5 text-right">{t('holdings.value', 'Value')}</th>
                  <th className="px-2 py-1.5 text-right">±%</th>
                  <th className="px-2 py-1.5 text-right" />
                </tr>
              </thead>
              <tbody className="tabular-nums">
                {holdings.map((h) => (
                  <tr key={h.id} className="border-t border-border/40 odd:bg-muted/10">
                    <td className="px-2 py-1.5 text-left font-medium">{h.label}</td>
                    <td className="px-2 py-1.5 text-left text-muted-foreground">{h.isin ?? '—'}</td>
                    <td className="px-2 py-1.5 text-left text-muted-foreground">
                      {h.quoteSymbol ?? '—'}
                    </td>
                    <td className="px-2 py-1.5 text-right">{h.quantity}</td>
                    <td className="px-2 py-1.5 text-right">
                      {h.lastPrice === null ? (
                        <span
                          className="text-muted-foreground"
                          title={t('holdings.noPrice', 'No price yet')}
                        >
                          —
                        </span>
                      ) : (
                        <span className={h.isStale ? 'text-amber-600 dark:text-amber-400' : undefined}>
                          {formatCurrency(h.lastPrice)}
                        </span>
                      )}
                    </td>
                    <td className="px-2 py-1.5 text-right">{formatCurrency(h.marketValue)}</td>
                    <td
                      className={`px-2 py-1.5 text-right ${
                        h.plusValuePct === null
                          ? 'text-muted-foreground'
                          : h.plusValuePct >= 0
                            ? 'text-emerald-600 dark:text-emerald-400'
                            : 'text-destructive'
                      }`}
                    >
                      {h.plusValuePct === null
                        ? '—'
                        : `${h.plusValuePct >= 0 ? '+' : ''}${h.plusValuePct.toFixed(1)}%`}
                    </td>
                    <td className="px-2 py-1.5 text-right whitespace-nowrap">
                      {deletingId === h.id ? (
                        <span className="inline-flex items-center gap-1">
                          <Button
                            type="button"
                            variant="destructive"
                            size="xs"
                            onClick={() => onConfirmDelete(h.id)}
                            disabled={deletePending}
                          >
                            {t('holdings.delete', 'Delete')}
                          </Button>
                          <Button
                            type="button"
                            variant="ghost"
                            size="xs"
                            onClick={() => setDeletingId(null)}
                            disabled={deletePending}
                          >
                            {t('common.cancel', 'Cancel')}
                          </Button>
                        </span>
                      ) : (
                        <span className="inline-flex items-center gap-1">
                          <Button
                            type="button"
                            variant="ghost"
                            size="xs"
                            onClick={() => openEditForm(h)}
                          >
                            {t('holdings.edit', 'Edit')}
                          </Button>
                          <Button
                            type="button"
                            variant="ghost"
                            size="xs"
                            className="text-muted-foreground hover:text-destructive"
                            onClick={() => setDeletingId(h.id)}
                          >
                            {t('holdings.delete', 'Delete')}
                          </Button>
                        </span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {/* ============================== form ============================= */}
        {showForm ? (
          <div className="space-y-3 rounded-lg border border-border/60 bg-muted/20 p-3">
            <h3 className="text-xs font-semibold uppercase tracking-wide text-muted-foreground">
              {editingId ? t('holdings.edit', 'Edit') : t('holdings.add', 'Add holding')}
            </h3>
            <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
              <div className="space-y-1">
                <Label htmlFor="holding-label">{t('holdings.label', 'Label')}</Label>
                <Input
                  id="holding-label"
                  value={draft.label}
                  onChange={(e) => setDraft((d) => ({ ...d, label: e.target.value }))}
                />
              </div>
              <div className="space-y-1">
                <Label htmlFor="holding-isin">{t('holdings.isin', 'ISIN')}</Label>
                <Input
                  id="holding-isin"
                  value={draft.isin}
                  onChange={(e) => setDraft((d) => ({ ...d, isin: e.target.value }))}
                />
              </div>
              <div className="space-y-1">
                <Label htmlFor="holding-symbol">{t('holdings.symbol', 'Symbol')}</Label>
                <Input
                  id="holding-symbol"
                  value={draft.quoteSymbol}
                  onChange={(e) => setDraft((d) => ({ ...d, quoteSymbol: e.target.value }))}
                  placeholder="WPEA.PA"
                />
              </div>
              <div className="space-y-1">
                <Label htmlFor="holding-quantity">{t('holdings.quantity', 'Quantity')}</Label>
                <Input
                  id="holding-quantity"
                  type="number"
                  step="any"
                  min="0"
                  value={draft.quantity}
                  onChange={(e) => setDraft((d) => ({ ...d, quantity: e.target.value }))}
                />
              </div>
              <div className="space-y-1">
                <Label htmlFor="holding-cost">{t('holdings.costBasis', 'Cost basis')}</Label>
                <Input
                  id="holding-cost"
                  type="number"
                  step="0.01"
                  min="0"
                  value={draft.costBasis}
                  onChange={(e) => setDraft((d) => ({ ...d, costBasis: e.target.value }))}
                />
              </div>
              <div className="space-y-1">
                <Label htmlFor="holding-currency">{t('common.status', 'Currency')}</Label>
                <Input
                  id="holding-currency"
                  value={draft.currency}
                  onChange={(e) => setDraft((d) => ({ ...d, currency: e.target.value }))}
                  placeholder="EUR"
                />
              </div>
            </div>
            <p className="text-[11px] text-muted-foreground">
              {t('holdings.priceOptIn', 'Only the ticker symbol is sent to fetch the price.')}
            </p>
            {formError && <p className="text-xs text-destructive">{formError}</p>}
            <div className="flex items-center gap-2">
              <Button type="button" size="sm" onClick={onSubmit} disabled={savePending}>
                {savePending ? t('common.saving', 'Saving…') : t('common.save', 'Save')}
              </Button>
              <Button
                type="button"
                variant="ghost"
                size="sm"
                onClick={closeForm}
                disabled={savePending}
              >
                {t('common.cancel', 'Cancel')}
              </Button>
            </div>
          </div>
        ) : (
          <Button type="button" variant="outline" size="sm" onClick={openAddForm}>
            {t('holdings.add', 'Add holding')}
          </Button>
        )}
      </CardContent>
    </Card>
  )
}

function Kpi({
  label,
  value,
  sublabel,
  tone,
}: {
  label: string
  value: string
  sublabel?: string
  tone?: 'positive' | 'negative'
}) {
  const toneClass =
    tone === 'positive'
      ? 'text-emerald-600 dark:text-emerald-400'
      : tone === 'negative'
        ? 'text-destructive'
        : ''
  return (
    <div className="rounded-md border border-border/60 bg-background p-3">
      <p className="text-[10px] uppercase tracking-wide text-muted-foreground">{label}</p>
      <p className={`mt-0.5 text-lg font-semibold ${toneClass}`}>{value}</p>
      {sublabel && <p className={`mt-0.5 text-[10px] ${toneClass || 'text-muted-foreground'}`}>{sublabel}</p>}
    </div>
  )
}
