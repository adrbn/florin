'use client'

import { useState } from 'react'
import { CheckCircle, FileKey, Unplug } from 'lucide-react'

interface BankingSettingsProps {
  configured: boolean
  currentAppId: string | null
}

export function BankingSettings({ configured, currentAppId }: BankingSettingsProps) {
  const [appId, setAppId] = useState(currentAppId ?? '')
  const [keyPath, setKeyPath] = useState('')
  const [saving, setSaving] = useState(false)
  const [status, setStatus] = useState<'idle' | 'saved' | 'error'>('idle')
  const [error, setError] = useState<string | null>(null)

  async function handlePickPem() {
    const dest = await window.florin?.importPem?.()
    if (dest) setKeyPath(dest)
  }

  async function handleSave() {
    if (!appId.trim() || !keyPath.trim()) {
      setError('Both App ID and private key are required.')
      return
    }
    setSaving(true)
    setError(null)
    try {
      const res = await fetch('/api/settings/banking', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ appId: appId.trim(), keyPath: keyPath.trim() }),
      })
      const data = await res.json()
      if (!data.success) throw new Error(data.error || 'Failed to save')
      setStatus('saved')
      setTimeout(() => setStatus('idle'), 3000)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save')
      setStatus('error')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="space-y-4 text-sm">
      {configured && (
        <div className="flex items-center gap-2 text-emerald-600 dark:text-emerald-400">
          <CheckCircle className="h-4 w-4" />
          <span>Banking API configured</span>
        </div>
      )}

      <div className="rounded-md border border-border bg-muted/30 p-3 text-xs text-muted-foreground">
        <strong className="text-foreground">Enable Banking (PSD2)</strong> — connect to EU banks to
        auto-import transactions. Your API credentials stay on this machine. Get credentials at{' '}
        <a
          href="https://enablebanking.com"
          target="_blank"
          rel="noopener noreferrer"
          className="text-primary hover:underline"
        >
          enablebanking.com
        </a>
      </div>

      <div className="space-y-3">
        <div className="space-y-1.5">
          <label htmlFor="eb-app-id" className="text-xs font-medium">
            App ID
          </label>
          <input
            id="eb-app-id"
            type="text"
            value={appId}
            onChange={(e) => setAppId(e.target.value)}
            placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
            className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm shadow-sm placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-ring"
          />
        </div>
        <div className="space-y-1.5">
          <label className="text-xs font-medium">RSA Private Key (.pem)</label>
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={handlePickPem}
              className="inline-flex items-center gap-2 rounded-md border border-input bg-background px-3 py-2 text-sm shadow-sm hover:bg-accent hover:text-accent-foreground"
            >
              <FileKey className="h-3.5 w-3.5" />
              {keyPath ? 'Change file...' : 'Import .pem file...'}
            </button>
            {keyPath && (
              <span className="truncate text-xs text-muted-foreground">{keyPath.split('/').pop()}</span>
            )}
            {!keyPath && configured && (
              <span className="text-xs text-muted-foreground">Key already imported</span>
            )}
          </div>
          <p className="text-[11px] text-muted-foreground">
            The key file is copied into Florin&apos;s secure data folder. The original is not modified.
          </p>
        </div>
      </div>

      {error && <p className="text-xs text-destructive">{error}</p>}
      {status === 'saved' && (
        <p className="text-xs text-emerald-600 dark:text-emerald-400">
          Saved. You can now connect bank accounts from the Accounts page.
        </p>
      )}

      <button
        type="button"
        onClick={handleSave}
        disabled={saving}
        className="inline-flex items-center gap-2 rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground shadow-sm transition-colors hover:bg-primary/90 disabled:opacity-50"
      >
        <Unplug className="h-3.5 w-3.5" />
        {saving ? 'Saving...' : configured ? 'Update Credentials' : 'Configure Banking'}
      </button>
    </div>
  )
}
