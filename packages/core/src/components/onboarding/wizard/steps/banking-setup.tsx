'use client'

import { useState } from 'react'

interface BankingSetupStepProps {
  onSave: (appId: string, keyPath: string) => Promise<void>
  onSkip: () => void
}

export function BankingSetupStep({ onSave, onSkip }: BankingSetupStepProps) {
  const [appId, setAppId] = useState('')
  const [keyPath, setKeyPath] = useState('')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function handleSave() {
    if (!appId.trim() || !keyPath.trim()) {
      setError('Both App ID and RSA key path are required.')
      return
    }
    setSaving(true)
    setError(null)
    try {
      await onSave(appId.trim(), keyPath.trim())
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save banking config')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="space-y-6">
      <div className="space-y-1">
        <h2 className="text-xl font-semibold">Enable Banking (optional)</h2>
        <p className="text-sm text-muted-foreground">
          Connect to EU banks via PSD2 to import transactions automatically. You can skip this and
          add everything manually.
        </p>
      </div>

      <div className="rounded-md border border-border bg-muted/30 p-3 text-xs text-muted-foreground">
        <strong className="text-foreground">PSD2 / Enable Banking</strong> — Florin uses the
        Enable Banking API to fetch transactions from your bank. Your credentials never leave your
        machine; the API key is stored locally and used only to sign requests.
      </div>

      <div className="space-y-4">
        <div className="space-y-1.5">
          <label htmlFor="app-id-input" className="text-sm font-medium">
            App ID
          </label>
          <input
            id="app-id-input"
            type="text"
            value={appId}
            onChange={(e) => setAppId(e.target.value)}
            placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
            className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm shadow-sm placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-ring"
          />
        </div>

        <div className="space-y-1.5">
          <label htmlFor="key-path-input" className="text-sm font-medium">
            RSA Private Key Path
          </label>
          <input
            id="key-path-input"
            type="text"
            value={keyPath}
            onChange={(e) => setKeyPath(e.target.value)}
            placeholder="/path/to/private.pem"
            className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm shadow-sm placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-ring"
          />
          <p className="text-[11px] text-muted-foreground">
            Absolute path to your RSA private key file (.pem).
          </p>
        </div>
      </div>

      {error && <p className="text-sm text-destructive">{error}</p>}

      <div className="flex gap-3">
        <button
          type="button"
          onClick={onSkip}
          className="flex-1 rounded-md border border-border bg-background px-4 py-2 text-sm font-medium text-foreground transition-colors hover:bg-muted"
        >
          Skip for now
        </button>
        <button
          type="button"
          onClick={handleSave}
          disabled={saving}
          className="flex-1 rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground transition-colors hover:bg-primary/90 disabled:opacity-50"
        >
          {saving ? 'Saving…' : 'Enable Banking'}
        </button>
      </div>
    </div>
  )
}
