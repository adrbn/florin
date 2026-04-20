'use client'

import { useMemo } from 'react'
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
}

/**
 * GitHub-style contribution heatmap for spending. Rows are weekdays
 * (Mon…Sun), columns are ISO weeks ordered left-to-right (oldest → today).
 * Future cells inside the current week are rendered as muted greys so the
 * grid stays rectangular without implying "no spend".
 *
 * The colour ramp is green→red so that a low-spend day reads "cool" (you
 * saved) and a big spend reads "hot". Null thresholds fall back to a
 * percentile of the observed data so the scale adapts to the user's
 * lifestyle rather than assuming everyone spends like the same person.
 */
export function WeeklyHeatmap({
  rows,
  weeks = 13,
  title,
  subtitle,
}: WeeklyHeatmapProps) {
  const t = useT()
  const effectiveTitle = title ?? t('reflect.heatmap.title', 'Spending heatmap')
  const effectiveSubtitle =
    subtitle ?? t('reflect.heatmap.subtitle', 'Cooler days = lower spend. Greyed cells are in the future.')

  const { matrix, stats } = useMemo(() => buildMatrix(rows, weeks), [rows, weeks])

  const dayLabels = [
    t('reflect.heatmap.mon', 'Mon'),
    '',
    t('reflect.heatmap.wed', 'Wed'),
    '',
    t('reflect.heatmap.fri', 'Fri'),
    '',
    t('reflect.heatmap.sun', 'Sun'),
  ]

  return (
    <Card>
      <CardHeader>
        <CardTitle>{effectiveTitle}</CardTitle>
        <p className="text-sm text-muted-foreground">{effectiveSubtitle}</p>
      </CardHeader>
      <CardContent>
        <div className="flex items-start gap-2">
          <div className="flex flex-col gap-[3px] pt-[2px] text-[10px] text-muted-foreground">
            {dayLabels.map((lbl, i) => (
              <div key={i} className="h-3 leading-3">
                {lbl}
              </div>
            ))}
          </div>
          <div
            className="grid gap-[3px]"
            style={{ gridTemplateColumns: `repeat(${weeks}, minmax(0, 1fr))` }}
          >
            {matrix.map((col, colIdx) => (
              <div key={colIdx} className="grid grid-rows-7 gap-[3px]">
                {col.map((cell, rowIdx) => (
                  <div
                    key={rowIdx}
                    title={
                      cell.future
                        ? ''
                        : cell.date
                          ? `${cell.date} — ${formatCurrency(cell.amount)}`
                          : ''
                    }
                    className="h-3 w-3 rounded-[3px]"
                    style={{ backgroundColor: cellColor(cell, stats) }}
                  />
                ))}
              </div>
            ))}
          </div>
        </div>
        <div className="mt-3 flex items-center gap-2 text-[10px] text-muted-foreground">
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

function buildMatrix(rows: ReadonlyArray<DailySpend>, weeks: number): { matrix: Cell[][]; stats: Stats } {
  const byDate = new Map<string, number>()
  for (const r of rows) byDate.set(r.date, r.amount)

  const today = new Date()
  const todayIso = toIso(today)
  // Anchor the grid at the most recent Sunday so columns line up week-by-week.
  const daysBackToSunday = today.getDay() // 0..6, 0 = Sun
  const anchor = new Date(today)
  anchor.setDate(anchor.getDate() + (6 - daysBackToSunday))
  // anchor is "this week's Saturday"
  const startCol = new Date(anchor)
  startCol.setDate(startCol.getDate() - 7 * (weeks - 1) - 6) // Monday of oldest week

  const matrix: Cell[][] = []
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
    matrix.push(col)
  }

  const amounts = matrix.flat().filter((c) => !c.future && c.amount > 0).map((c) => c.amount)
  amounts.sort((a, b) => a - b)
  const p90 = amounts.length > 0 ? amounts[Math.floor(amounts.length * 0.9)] ?? 0 : 0
  return { matrix, stats: { p90 } }
}

function toIso(d: Date): string {
  const yyyy = d.getFullYear()
  const mm = String(d.getMonth() + 1).padStart(2, '0')
  const dd = String(d.getDate()).padStart(2, '0')
  return `${yyyy}-${mm}-${dd}`
}

function cellColor(cell: Cell, stats: Stats): string {
  if (cell.future) return 'rgb(229 231 235 / 0.3)' // muted grey
  if (cell.amount === 0) return 'rgb(148 163 184 / 0.18)'
  const normalized = stats.p90 > 0 ? Math.min(cell.amount / stats.p90, 1) : 0
  return rampColor(normalized)
}

/**
 * 0 → green, 0.5 → amber, 1 → red. Hand-picked stops in sRGB so the
 * midtone doesn't desaturate to grey the way a plain HSL interpolation
 * would.
 */
function rampColor(p: number): string {
  const stops = [
    { at: 0, r: 16, g: 185, b: 129 }, // emerald-500
    { at: 0.5, r: 245, g: 158, b: 11 }, // amber-500
    { at: 1, r: 239, g: 68, b: 68 }, // red-500
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
