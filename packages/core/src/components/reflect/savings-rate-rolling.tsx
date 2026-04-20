import { Card, CardContent, CardHeader, CardTitle } from '../ui/card'
import type { SavingsRates } from '../../types/index'

interface SavingsRateRollingProps {
  rates: SavingsRates
  title: string
  subtitle: string
  labels: {
    threeMonth: string
    sixMonth: string
    twelveMonth: string
    noData: string
  }
}

/**
 * Three-bucket savings-rate indicator: how much of income was saved over
 * rolling 3/6/12-month windows. Null windows show a neutral dash rather
 * than a misleading 0% — happens when the user had no income in that
 * period (e.g. a student month, or early in a fresh Florin install).
 */
export function SavingsRateRolling({ rates, title, subtitle, labels }: SavingsRateRollingProps) {
  const cells: Array<{ label: string; value: number | null }> = [
    { label: labels.threeMonth, value: rates.threeMonth },
    { label: labels.sixMonth, value: rates.sixMonth },
    { label: labels.twelveMonth, value: rates.twelveMonth },
  ]

  return (
    <Card>
      <CardHeader>
        <CardTitle>{title}</CardTitle>
        <p className="text-sm text-muted-foreground">{subtitle}</p>
      </CardHeader>
      <CardContent>
        <div className="grid grid-cols-3 gap-3">
          {cells.map((c) => (
            <div key={c.label} className="rounded-md border border-border bg-muted/20 p-3">
              <div className="text-[11px] uppercase tracking-wide text-muted-foreground">
                {c.label}
              </div>
              <div
                className="mt-1 text-2xl font-bold tabular-nums"
                style={{ color: toneColor(c.value) }}
              >
                {c.value === null ? '—' : `${Math.round(c.value)}%`}
              </div>
              {c.value === null ? (
                <div className="text-[10px] text-muted-foreground">{labels.noData}</div>
              ) : null}
            </div>
          ))}
        </div>
      </CardContent>
    </Card>
  )
}

function toneColor(v: number | null): string | undefined {
  if (v === null) return undefined
  if (v >= 20) return 'rgb(16 185 129)' // emerald-500
  if (v >= 0) return 'rgb(245 158 11)' // amber-500
  return 'rgb(239 68 68)' // red-500
}
