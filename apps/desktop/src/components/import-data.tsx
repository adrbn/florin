'use client'

import { useState, useRef } from 'react'
import { useRouter } from 'next/navigation'

export function ImportData() {
  const router = useRouter()
  const fileRef = useRef<HTMLInputElement>(null)
  const [status, setStatus] = useState<'idle' | 'importing' | 'success' | 'error'>('idle')
  const [message, setMessage] = useState('')

  async function handleImport() {
    const file = fileRef.current?.files?.[0]
    if (!file) return

    setStatus('importing')
    setMessage('')

    try {
      const text = await file.text()
      const payload = JSON.parse(text)

      const res = await fetch('/api/import/json', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      })

      const data = await res.json()

      if (!res.ok) {
        setStatus('error')
        setMessage(data.error || 'Import failed')
        return
      }

      const { imported } = data
      setStatus('success')
      setMessage(
        `Imported ${imported.accounts} accounts, ${imported.transactions} transactions, ${imported.categories} categories, ${imported.rules} rules`,
      )
      // Refresh to show new data
      window.location.href = '/'
    } catch (err) {
      setStatus('error')
      setMessage(err instanceof Error ? err.message : 'Failed to parse file')
    }
  }

  return (
    <div className="space-y-3">
      <p className="text-sm text-muted-foreground">
        Import a Florin JSON export file. This replaces all existing data (except PIN and locale settings).
      </p>
      <div className="flex items-center gap-2">
        <input
          ref={fileRef}
          type="file"
          accept=".json"
          className="text-sm file:mr-2 file:rounded-md file:border file:border-input file:bg-background file:px-3 file:py-1.5 file:text-sm file:font-medium file:text-foreground hover:file:bg-accent"
        />
        <button
          type="button"
          onClick={handleImport}
          disabled={status === 'importing'}
          className="rounded-md border border-input bg-background px-3 py-1.5 text-sm font-medium hover:bg-accent hover:text-accent-foreground disabled:opacity-50"
        >
          {status === 'importing' ? 'Importing…' : 'Import'}
        </button>
      </div>
      {message && (
        <p className={`text-xs ${status === 'error' ? 'text-destructive' : 'text-emerald-600'}`}>
          {message}
        </p>
      )}
    </div>
  )
}
