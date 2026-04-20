'use client'

import Link from 'next/link'
import { useEffect, useMemo, useRef, useState } from 'react'
import { Filter } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '../ui/card'
import { Button } from '../ui/button'
import { formatCurrency } from '../../lib/format/currency'
import { useT } from '../../i18n/context'
import type { DailyCategorySpend } from '../../types/index'

interface CategoryOption {
  categoryId: string
  categoryName: string
  groupName: string | null
}

interface FilterPreset {
  id: string
  label: string
  /** Returns the set of categoryIds to EXCLUDE for this preset. */
  match: (cats: ReadonlyArray<CategoryOption>) => Set<string>
}

interface WeeklyHeatmapProps {
  /** Per-day per-category spend rows; heatmap aggregates client-side. */
  rows: ReadonlyArray<DailyCategorySpend>
  /** How many weeks (including the current one) to show. */
  weeks?: number
  title?: string
  subtitle?: string
  /** BCP47 locale for formatting date labels and months. */
  locale?: string
}

export function WeeklyHeatmap({
  rows,
  weeks = 52,
  title,
  subtitle,
  locale,
}: WeeklyHeatmapProps) {
  const t = useT()
  const effectiveTitle = title ?? t('reflect.heatmap.title', 'Spending heatmap')
  const effectiveSubtitle =
    subtitle ??
    t('reflect.heatmap.subtitle', 'Cooler days = lower spend. Click a cell to inspect that day.')

  const categories = useMemo(() => {
    const map = new Map<string, CategoryOption>()
    for (const r of rows) {
      if (!r.categoryId) continue
      if (!map.has(r.categoryId)) {
        map.set(r.categoryId, {
          categoryId: r.categoryId,
          categoryName: r.categoryName ?? '—',
          groupName: r.groupName ?? null,
        })
      }
    }
    return Array.from(map.values()).sort((a, b) =>
      a.categoryName.localeCompare(b.categoryName),
    )
  }, [rows])

  const presets: FilterPreset[] = useMemo(
    () => [
      {
        id: 'no-rent',
        label: t('reflect.heatmap.presetNoRent', 'Without rent'),
        match: (cats) => {
          const out = new Set<string>()
          for (const c of cats) {
            const n = c.categoryName.toLowerCase()
            const g = (c.groupName ?? '').toLowerCase()
            if (/(loyer|rent|hypoth)/.test(n) || /(housing|logement)/.test(g)) {
              out.add(c.categoryId)
            }
          }
          return out
        },
      },
    ],
    [t],
  )

  const [excluded, setExcluded] = useState<Set<string>>(new Set())
  const [filterOpen, setFilterOpen] = useState(false)

  const dailyTotals = useMemo(() => {
    const by = new Map<string, number>()
    for (const r of rows) {
      if (r.categoryId && excluded.has(r.categoryId)) continue
      by.set(r.date, (by.get(r.date) ?? 0) + r.amount)
    }
    return by
  }, [rows, excluded])

  const { matrix, stats, monthLabels } = useMemo(
    () => buildMatrix(dailyTotals, weeks, locale),
    [dailyTotals, weeks, locale],
  )

  const [selected, setSelected] = useState<SelectedCell | null>(null)
  const [hovered, setHovered] = useState<HoveredCell | null>(null)
  const gridRef = useRef<HTMLDivElement | null>(null)

  useEffect(() => {
    if (!selected) return
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setSelected(null)
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [selected])

  const dateFmt = useMemo(
    () => new Intl.DateTimeFormat(locale, { weekday: 'long', day: 'numeric', month: 'long' }),
    [locale],
  )

  const dayLabels = [
    t('reflect.heatmap.mon', 'Mon'),
    '',
    t('reflect.heatmap.wed', 'Wed'),
    '',
    t('reflect.heatmap.fri', 'Fri'),
    '',
    t('reflect.heatmap.sun', 'Sun'),
  ]

  const activeExcludedCount = excluded.size
  const clearLabel = t('common.clear', 'Clear')
  const filterLabel = t('reflect.heatmap.filter', 'Filter')

  return (
    <Card>
      <CardHeader>
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div className="min-w-0">
            <CardTitle>{effectiveTitle}</CardTitle>
            <p className="text-sm text-muted-foreground">{effectiveSubtitle}</p>
          </div>
          <div className="relative">
            <Button
              variant="outline"
              size="sm"
              className="gap-2"
              onClick={() => setFilterOpen((v) => !v)}
            >
              <Filter className="h-3.5 w-3.5" />
              {filterLabel}
              {activeExcludedCount > 0 ? (
                <span className="rounded-full bg-foreground px-1.5 text-[10px] font-medium text-background">
                  −{activeExcludedCount}
                </span>
              ) : null}
            </Button>
            {filterOpen ? (
              <>
                <div
                  className="fixed inset-0 z-40"
                  onClick={() => setFilterOpen(false)}
                  aria-hidden="true"
                />
                <div className="absolute right-0 top-full z-50 mt-2 max-h-[400px] w-72 overflow-auto rounded-lg border bg-popover p-3 text-xs shadow-lg ring-1 ring-foreground/5">
                  <div className="mb-2 flex items-center justify-between gap-2">
                    <span className="text-sm font-medium">
                      {t('reflect.heatmap.excludeCategories', 'Exclude categories')}
                    </span>
                    {excluded.size > 0 ? (
                      <button
                        type="button"
                        className="text-[11px] text-muted-foreground hover:text-foreground"
                        onClick={() => setExcluded(new Set())}
                      >
                        {clearLabel}
                      </button>
                    ) : null}
                  </div>
                  <div className="mb-3 flex flex-wrap gap-1.5">
                    {presets.map((p) => {
                      const presetIds = p.match(categories)
                      const active =
                        presetIds.size > 0 &&
                        [...presetIds].every((id) => excluded.has(id))
                      return (
                        <button
                          key={p.id}
                          type="button"
                          onClick={() =>
                            setExcluded((prev) => {
                              const next = new Set(prev)
                              if (active) {
                                for (const id of presetIds) next.delete(id)
                              } else {
                                for (const id of presetIds) next.add(id)
                              }
                              return next
                            })
                          }
                          className={`rounded-full border px-2 py-0.5 text-[11px] transition-colors ${
                            active
                              ? 'border-foreground bg-foreground text-background'
                              : 'border-border hover:border-foreground/40'
                          }`}
                        >
                          {p.label}
                        </button>
                      )
                    })}
                  </div>
                  <ul className="space-y-1">
                    {categories.length === 0 ? (
                      <li className="text-muted-foreground">
                        {t('reflect.heatmap.noCategories', 'No categorised spending in range.')}
                      </li>
                    ) : (
                      categories.map((c) => {
                        const on = excluded.has(c.categoryId)
                        return (
                          <li key={c.categoryId}>
                            <label className="flex cursor-pointer items-center gap-2 rounded px-1.5 py-1 hover:bg-muted/40">
                              <input
                                type="checkbox"
                                checked={on}
                                onChange={() =>
                                  setExcluded((prev) => {
                                    const next = new Set(prev)
                                    if (next.has(c.categoryId)) next.delete(c.categoryId)
                                    else next.add(c.categoryId)
                                    return next
                                  })
                                }
                              />
                              <span className="min-w-0 flex-1 truncate">{c.categoryName}</span>
                              {c.groupName ? (
                                <span className="text-[10px] text-muted-foreground">
                                  {c.groupName}
                                </span>
                              ) : null}
                            </label>
                          </li>
                        )
                      })
                    )}
                  </ul>
                </div>
              </>
            ) : null}
          </div>
        </div>
      </CardHeader>
      <CardContent>
        <div className="relative" ref={gridRef}>
          {/* Month labels row, sized to match the grid column width. */}
          <div
            className="mb-1 grid h-3 pl-7 text-[10px] text-muted-foreground"
            style={{ gridTemplateColumns: `repeat(${weeks}, minmax(0, 1fr))` }}
          >
            {monthLabels.map((m, i) => (
              <div key={i} className="relative leading-none">
                {m ? <span className="absolute left-0 top-0 whitespace-nowrap">{m}</span> : null}
              </div>
            ))}
          </div>
          <div className="flex items-stretch gap-1">
            {/* Day labels: grid-rows-7 so each label aligns with the cell row it describes. */}
            <div className="grid w-6 grid-rows-7 gap-[2px] text-[10px] leading-none text-muted-foreground">
              {dayLabels.map((lbl, i) => (
                <div key={i} className="flex items-center">
                  {lbl}
                </div>
              ))}
            </div>
            <div
              className="grid min-w-0 flex-1 gap-[2px]"
              style={{ gridTemplateColumns: `repeat(${weeks}, minmax(0, 1fr))` }}
            >
              {matrix.map((col, colIdx) => (
                <div key={colIdx} className="grid grid-rows-7 gap-[2px]">
                  {col.map((cell, rowIdx) => {
                    const isFocused =
                      selected && cell.date && selected.date === cell.date
                    return (
                      <button
                        type="button"
                        key={rowIdx}
                        disabled={cell.future || !cell.date}
                        onMouseEnter={(e) => {
                          if (cell.future || !cell.date) return
                          const rect = e.currentTarget.getBoundingClientRect()
                          const parentRect =
                            gridRef.current?.getBoundingClientRect() ?? rect
                          setHovered({
                            date: cell.date,
                            amount: cell.amount,
                            x: rect.left - parentRect.left + rect.width / 2,
                            y: rect.top - parentRect.top,
                          })
                        }}
                        onMouseLeave={() => setHovered(null)}
                        onClick={(e) => {
                          if (cell.future || !cell.date) return
                          const rect = e.currentTarget.getBoundingClientRect()
                          const parentRect =
                            gridRef.current?.getBoundingClientRect() ?? rect
                          const gridHeight = parentRect.height
                          const cellBottomInParent = rect.bottom - parentRect.top
                          const cellTopInParent = rect.top - parentRect.top
                          const cellWidth = rect.width
                          // Anchor below by default; flip above if we'd overflow the card
                          const below = gridHeight - cellBottomInParent > 120
                          const cellCenterX = rect.left - parentRect.left + cellWidth / 2
                          setSelected({
                            date: cell.date,
                            amount: cell.amount,
                            x: cellCenterX,
                            y: below ? cellBottomInParent + 6 : cellTopInParent - 6,
                            below,
                          })
                          setHovered(null)
                        }}
                        className={`aspect-square w-full rounded-[3px] outline-offset-1 ${
                          isFocused
                            ? 'outline outline-2 outline-foreground'
                            : 'hover:outline hover:outline-1 hover:outline-foreground/40'
                        } ${cell.future || !cell.date ? 'cursor-default' : 'cursor-pointer'}`}
                        style={{ backgroundColor: cellColor(cell, stats) }}
                        aria-label={
                          cell.future || !cell.date
                            ? undefined
                            : `${dateFmt.format(new Date(cell.date))} ${formatCurrency(cell.amount)}`
                        }
                      />
                    )
                  })}
                </div>
              ))}
            </div>
          </div>

          {hovered && !selected ? (
            <div
              className="pointer-events-none absolute z-30 -translate-x-1/2 -translate-y-full rounded-md border bg-popover px-2 py-1 text-[11px] shadow-md ring-1 ring-foreground/5"
              style={{ left: hovered.x, top: hovered.y - 4 }}
            >
              <div className="font-medium">{dateFmt.format(new Date(hovered.date))}</div>
              <div className="tabular-nums text-muted-foreground">
                {hovered.amount > 0
                  ? formatCurrency(hovered.amount)
                  : t('reflect.heatmap.noSpend', 'No spending')}
              </div>
            </div>
          ) : null}

          {selected ? (
            <>
              <div
                className="fixed inset-0 z-40"
                onClick={() => setSelected(null)}
                aria-hidden="true"
              />
              <div
                className="absolute z-50 w-56 -translate-x-1/2 rounded-lg border bg-popover p-3 text-xs shadow-lg ring-1 ring-foreground/5"
                style={{
                  left: selected.x,
                  top: selected.y,
                  transform: selected.below
                    ? 'translate(-50%, 0)'
                    : 'translate(-50%, -100%)',
                }}
                role="dialog"
              >
                <div className="mb-1 text-sm font-medium">
                  {dateFmt.format(new Date(selected.date))}
                </div>
                <div className="mb-2 tabular-nums">
                  {selected.amount > 0
                    ? formatCurrency(selected.amount)
                    : t('reflect.heatmap.noSpend', 'No spending')}
                </div>
                <Link
                  href={{
                    pathname: '/transactions',
                    query: { from: selected.date, to: selected.date, direction: 'expense' },
                  }}
                  className="inline-flex w-full items-center justify-center rounded-md bg-foreground px-2 py-1.5 text-[11px] font-medium text-background hover:bg-foreground/90"
                >
                  {t('reflect.heatmap.viewTxs', 'View transactions')}
                </Link>
              </div>
            </>
          ) : null}
        </div>

        <div className="mt-3 flex items-center justify-end gap-1.5 text-[10px] text-muted-foreground">
          <span>{t('reflect.heatmap.less', 'Less')}</span>
          {[0, 0.25, 0.5, 0.75, 1].map((p) => (
            <div
              key={p}
              className="h-3 w-3 rounded-[3px]"
              style={{ backgroundColor: rampColor(p) }}
            />
          ))}
          <span>{t('reflect.heatmap.more', 'More')}</span>
        </div>
      </CardContent>
    </Card>
  )
}

interface Cell {
  date: string | null
  amount: number
  future: boolean
}

interface Stats {
  p90: number
}

interface SelectedCell {
  date: string
  amount: number
  x: number
  y: number
  below: boolean
}

interface HoveredCell {
  date: string
  amount: number
  x: number
  y: number
}

function buildMatrix(
  byDate: Map<string, number>,
  weeks: number,
  locale: string | undefined,
): { matrix: Cell[][]; stats: Stats; monthLabels: string[] } {
  const today = new Date()
  const todayIso = toIso(today)
  const daysToSaturday = 6 - today.getDay()
  const anchor = new Date(today)
  anchor.setDate(anchor.getDate() + daysToSaturday)
  const startCol = new Date(anchor)
  startCol.setDate(startCol.getDate() - 7 * (weeks - 1) - 6)

  const monthFmt = new Intl.DateTimeFormat(locale, { month: 'short' })
  const matrix: Cell[][] = []
  const monthLabels: string[] = []
  let lastMonth = -1
  for (let w = 0; w < weeks; w += 1) {
    const col: Cell[] = []
    for (let d = 0; d < 7; d += 1) {
      const cursor = new Date(startCol)
      cursor.setDate(startCol.getDate() + w * 7 + d)
      const iso = toIso(cursor)
      const future = iso > todayIso
      col.push({
        date: iso,
        amount: byDate.get(iso) ?? 0,
        future,
      })
    }
    const colMonth = new Date(startCol)
    colMonth.setDate(startCol.getDate() + w * 7)
    const m = colMonth.getMonth()
    if (m !== lastMonth) {
      monthLabels.push(monthFmt.format(colMonth))
      lastMonth = m
    } else {
      monthLabels.push('')
    }
    matrix.push(col)
  }

  const amounts = matrix.flat().filter((c) => !c.future && c.amount > 0).map((c) => c.amount)
  amounts.sort((a, b) => a - b)
  const p90 = amounts.length > 0 ? amounts[Math.floor(amounts.length * 0.9)] ?? 0 : 0
  return { matrix, stats: { p90 }, monthLabels }
}

function toIso(d: Date): string {
  const yyyy = d.getFullYear()
  const mm = String(d.getMonth() + 1).padStart(2, '0')
  const dd = String(d.getDate()).padStart(2, '0')
  return `${yyyy}-${mm}-${dd}`
}

function cellColor(cell: Cell, stats: Stats): string {
  if (cell.future) return 'rgb(148 163 184 / 0.12)'
  if (cell.amount === 0) return 'rgb(148 163 184 / 0.18)'
  const normalized = stats.p90 > 0 ? Math.min(cell.amount / stats.p90, 1) : 0
  return rampColor(normalized)
}

function rampColor(p: number): string {
  const stops = [
    { at: 0, r: 16, g: 185, b: 129 },
    { at: 0.5, r: 245, g: 158, b: 11 },
    { at: 1, r: 239, g: 68, b: 68 },
  ]
  let a = stops[0]!
  let b = stops[stops.length - 1]!
  for (let i = 0; i < stops.length - 1; i += 1) {
    if (p >= stops[i]!.at && p <= stops[i + 1]!.at) {
      a = stops[i]!
      b = stops[i + 1]!
      break
    }
  }
  const span = b.at - a.at
  const t = span === 0 ? 0 : (p - a.at) / span
  const r = Math.round(a.r + (b.r - a.r) * t)
  const g = Math.round(a.g + (b.g - a.g) * t)
  const bl = Math.round(a.b + (b.b - a.b) * t)
  return `rgb(${r} ${g} ${bl})`
}
