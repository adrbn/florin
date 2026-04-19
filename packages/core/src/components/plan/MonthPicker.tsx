'use client'

import { ChevronLeft, ChevronRight } from 'lucide-react'
import { useT } from '../../i18n/context'

interface MonthPickerProps {
  year: number
  month: number
  onChange: (year: number, month: number) => void
}

const MONTH_KEYS = [
  'plan.monthJanuary',
  'plan.monthFebruary',
  'plan.monthMarch',
  'plan.monthAprilLong',
  'plan.monthMayLong',
  'plan.monthJuneLong',
  'plan.monthJulyLong',
  'plan.monthAugustLong',
  'plan.monthSeptember',
  'plan.monthOctober',
  'plan.monthNovember',
  'plan.monthDecember',
]
const MONTH_FALLBACKS = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
]

export function MonthPicker({ year, month, onChange }: MonthPickerProps) {
  const t = useT()
  function shift(delta: number) {
    let m = month + delta
    let y = year
    while (m > 12) { m -= 12; y += 1 }
    while (m < 1) { m += 12; y -= 1 }
    onChange(y, m)
  }

  const monthName = t(MONTH_KEYS[month - 1]!, MONTH_FALLBACKS[month - 1]!)

  return (
    <div className="flex items-center justify-center gap-2 py-2 px-4">
      <button
        type="button"
        onClick={() => shift(-1)}
        aria-label={t('plan.previousMonth', 'Previous month')}
        className="h-8 w-8 rounded-full hover:bg-muted flex items-center justify-center"
      >
        <ChevronLeft size={18} />
      </button>
      <div className="text-sm font-semibold min-w-[140px] text-center">
        {monthName} {year}
      </div>
      <button
        type="button"
        onClick={() => shift(1)}
        aria-label={t('plan.nextMonth', 'Next month')}
        className="h-8 w-8 rounded-full hover:bg-muted flex items-center justify-center"
      >
        <ChevronRight size={18} />
      </button>
    </div>
  )
}
