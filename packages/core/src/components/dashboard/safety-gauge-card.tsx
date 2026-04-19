import { Shield } from 'lucide-react'
import { KpiCard, type KpiTone } from './kpi-card'

function tone(months: number): KpiTone {
  if (months > 24) return 'positive'
  if (months > 6) return 'default'
  return 'negative'
}

function format(months: number, monthsLabel: string, yearsLabel: string): string {
  if (months <= 0) return '—'
  if (months >= 24) {
    const years = months / 12
    return `${years.toFixed(1)} ${yearsLabel}`
  }
  return `${Math.round(months)} ${monthsLabel}`
}

interface SafetyGaugeCardProps {
  net: number
  avgBurn: number
  title?: string
  hint?: string
  monthsLabel?: string
  yearsLabel?: string
}

export function SafetyGaugeCard({
  net,
  avgBurn,
  title = 'Safety gauge',
  hint = 'How long net worth covers your average burn rate',
  monthsLabel = 'months',
  yearsLabel = 'years',
}: SafetyGaugeCardProps) {
  const months = avgBurn > 0 ? net / avgBurn : 0
  return (
    <KpiCard
      title={title}
      value={format(months, monthsLabel, yearsLabel)}
      hint={hint}
      icon={Shield}
      tone={tone(months)}
    />
  )
}
