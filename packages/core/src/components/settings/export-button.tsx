'use client'

import { useState, useTransition } from 'react'
import { Button } from '../ui/button'
import { useT } from '../../i18n/context'

/**
 * Triggers a JSON download of every Florin table. Done client-side because
 * we need a Blob + anchor click to actually save the file — server actions
 * can't push a file to the browser.
 */
interface ExportButtonProps {
  onExportAllData: () => Promise<unknown>
}

export function ExportButton({ onExportAllData }: ExportButtonProps) {
  const t = useT()
  const [pending, startTransition] = useTransition()
  const [error, setError] = useState<string | null>(null)

  const onClick = () => {
    setError(null)
    startTransition(async () => {
      try {
        const payload = await onExportAllData()
        const blob = new Blob([JSON.stringify(payload, null, 2)], {
          type: 'application/json',
        })
        const url = URL.createObjectURL(blob)
        const stamp = new Date().toISOString().slice(0, 10)
        const a = document.createElement('a')
        a.href = url
        a.download = `florin-export-${stamp}.json`
        document.body.appendChild(a)
        a.click()
        a.remove()
        URL.revokeObjectURL(url)
      } catch (err: unknown) {
        const message = err instanceof Error ? err.message : t('settings.exportFailed', 'Export failed')
        setError(message)
      }
    })
  }

  return (
    <div className="space-y-1">
      <Button onClick={onClick} disabled={pending} variant="outline" size="sm">
        {pending
          ? t('settings.exporting', 'Exporting…')
          : t('settings.exportButton', 'Export all data (JSON)')}
      </Button>
      {error && <p className="text-xs text-destructive">{error}</p>}
    </div>
  )
}
