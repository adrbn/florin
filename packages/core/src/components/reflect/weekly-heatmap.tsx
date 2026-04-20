'use client'

import Link from 'next/link'
import { useEffect, useMemo, useRef, useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '../ui/card'
import { formatCurrency } from '../../lib/format/currency'
import { useT } from '../../i18n/context'
import type { DailySpend } from '../../types/index'

interface WeeklyHeatmapProps {
  /** Raw per-day spend from the query. Missing days are rendered as 0. */
  rows: ReadonlyArray<DailySpend>
  /** How many weeks (including the current one) to show. */
  weeks?: number
  title?: string
  subtitle?: string
  /**
   * Locale for month/day formatting. Defaults to the browser/user locale.
   * Passing it from the page keeps SSR output stable.
   */
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

  const { matrix, stats, monthLabels } = useMemo(
    () => buildMatrix(rows, weeks, locale),
    [rows, weeks, locale],
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

  const [selected, setSelected] = useState<SelectedCell | null>(null)
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

  return (
    <Card>
      <CardHeader>
        <CardTitle>{effectiveTitle}</CardTitle>
        <p className="text-sm text-muted-foreground">{effectiveSubtitle}</p>
      </CardHeader>
      <CardContent>
        <div className="relative" ref={gridRef}>
          <div className="flex items-start gap-1.5">
            <div className="flex flex-col justify-between gap-[2px] pt-5 text-[10px] text-muted-foreground">
              {dayLabels.map((lbl, i) => (
                <div key={i} className="flex-1 leading-none">
                  {lbl}
                </div>
              ))}
            </div>
            <div className="min-w-0 flex-1">
              <div
                className="relative grid h-4 text-[10px] text-muted-foreground"
                style={{ gridTemplateColumns: `repeat(${weeks}, minmax(0, 1fr))` }}
              >
                {monthLabels.map((m, i) =>
                  m ? (
                    <span
                      key={i}
                      className="pointer-events-none absolute top-0 leading-none"
                      style={{ left: `calc((100% / ${weeks}) * ${i})` }}
                    >
                      {m}
                    </span>
                  ) : null,
                )}
              </div>
              <div
                className="grid gap-[2px]"
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
                          onClick={(e) => {
                            if (cell.future || !cell.date) return
                            const rect = e.currentTarget.getBoundingClientRect()
                            const parentRect =
                              gridRef.current?.getBoundingClientRect() ?? rect
                            setSelected({
                              date: cell.date,
                              amount: cell.amount,
                              x: rect.left - parentRect.left + rect.width / 2,
                              y: rect.bottom - parentRect.top + 6,
                            })
                          }}
                          title={
                            cell.future || !cell.date
                              ? ''
                              : `${dateFmt.format(new Date(cell.date))} · ${formatCurrency(cell.amount)}`
                          }
                          className={`aspect-square w-full rounded-[3px] transition-[outline] outline-offset-1 ${
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
          </div>

          {selected ? (
            <>
              <div
                className="fixed inset-0 z-40"
                onClick={() => setSelected(null)}
                aria-hidden="true"
              />
              <div
                className="absolute z-50 w-56 -translate-x-1/2 rounded-lg border bg-popover p-3 text-xs shadow-lg ring-1 ring-foreground/5"
                style={{ left: selected.x, top: selected.y }}
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
}

function buildMatrix(
  rows: ReadonlyArray<DailySpend>,
  weeks: number,
  locale: string | undefined,
): { matrix: Cell[][]; stats: Stats; monthLabels: string[] } {
  const byDate = new Map<string, number>()
  for (const r of rows) byDate.set(r.date, r.amount)

  const today = new Date()
  const todayIso = toIso(today)
  // Anchor the grid on the Saturday of the current week so each column is
  // Mon..Sun and "today" lives in the rightmost column.
  const daysToSaturday = 6 - today.getDay()
  const anchor = new Date(today)
  anchor.setDate(anchor.getDate() + daysToSaturday)
  const startCol = new Date(anchor)
  startCol.setDate(startCol.getDate() - 7 * (weeks - 1) - 6) // Monday of oldest week

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
    // Column "owns" the month of its Monday (first cell)
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
