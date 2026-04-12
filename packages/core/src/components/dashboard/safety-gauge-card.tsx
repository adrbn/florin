import { Shield } from 'lucide-react'
import { KpiCard, type KpiTone } from './kpi-card'

function tone(months: number): KpiTone {
  if (months > 24) return 'positive'
  if (months > 6) return 'default'
  return 'negative'
}

function format(months: number): string {
  if (months <= 0) return '—'
  if (months >= 24) {
    const years = months / 12
    return `${years.toFixed(1)} years`
  }
  return `${Math.round(months)} months`
}

interface SafetyGaugeCardProps {
  net: number
  avgBurn: number
}

export function SafetyGaugeCard({ net, avgBurn }: SafetyGaugeCardProps) {
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
