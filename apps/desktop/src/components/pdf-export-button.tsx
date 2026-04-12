'use client'

import { FileDown } from 'lucide-react'

interface PdfExportButtonProps {
  month?: string // YYYY-MM
}

export function PdfExportButton({ month }: PdfExportButtonProps) {
  const now = new Date()
  const defaultMonth = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`
  const target = month ?? defaultMonth

  function handleExport() {
    window.open(`/api/export/pdf?month=${target}`, '_blank')
  }

  return (
    <button
      type="button"
      onClick={handleExport}
      className="inline-flex items-center gap-2 rounded-md border border-border px-3 py-1.5 text-sm font-medium transition-colors hover:bg-muted"
    >
      <FileDown className="h-4 w-4" />
      Export PDF Report
    </button>
  )
}
