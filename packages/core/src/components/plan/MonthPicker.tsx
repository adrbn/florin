'use client'

import { ChevronLeft, ChevronRight } from 'lucide-react'

interface MonthPickerProps {
  year: number
  month: number
  onChange: (year: number, month: number) => void
}

const MONTH_NAMES = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
]

export function MonthPicker({ year, month, onChange }: MonthPickerProps) {
  function shift(delta: number) {
    let m = month + delta
    let y = year
    while (m > 12) { m -= 12; y += 1 }
    while (m < 1) { m += 12; y -= 1 }
    onChange(y, m)
  }

  return (
    <div className="flex items-center justify-center gap-2 py-2 px-4">
      <button
        type="button"
        onClick={() => shift(-1)}
        aria-label="Previous month"
        className="h-8 w-8 rounded-full hover:bg-muted flex items-center justify-center"
      >
        <ChevronLeft size={18} />
      </button>
      <div className="text-sm font-semibold min-w-[140px] text-center">
        {MONTH_NAMES[month - 1]} {year}
      </div>
      <button
        type="button"
        onClick={() => shift(1)}
        aria-label="Next month"
        className="h-8 w-8 rounded-full hover:bg-muted flex items-center justify-center"
      >
        <ChevronRight size={18} />
      </button>
    </div>
  )
}
