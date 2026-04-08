import { Shield } from 'lucide-react'
import { getAvgMonthlyBurn, getNetWorth } from '@/server/queries/dashboard'
import { KpiCard, type KpiTone } from './kpi-card'

function tone(months: number): KpiTone {
  if (months > 24) return 'positive'
  if (months > 6) return 'default'
  return 'negative'
}

/**
 * "How much runway does the user have if income stops?" — net worth divided
 * by the average monthly burn over the last 6 months. Display in years when
 * the runway is long enough that "months" reads as a wall of digits, otherwise
 * in months for finer resolution.
 */
function format(months: number): string {
  if (months <= 0) return '—'
  if (months >= 24) {
    const years = months / 12
    return `${years.toFixed(1)} years`
  }
  return `${Math.round(months)} months`
}

export async function SafetyGaugeCard() {
  const [{ net }, avgBurn] = await Promise.all([getNetWorth(), getAvgMonthlyBurn(6)])
  const months = avgBurn > 0 ? net / avgBurn : 0
  return (
    <KpiCard
      title="Safety gauge"
      value={format(months)}
      hint="How long net worth covers your average burn rate"
      icon={Shield}
      tone={tone(months)}
    />
  )
}
