'use client'

import { useState } from 'react'
import { CheckCircle, Copy, FileKey, KeyRound, Unplug } from 'lucide-react'
import { useT } from '@florin/core/i18n/context'

interface BankingSettingsProps {
  configured: boolean
  currentAppId: string | null
}

const REDIRECT_URI = 'https://127.0.0.1:3847/api/banking/callback'

export function BankingSettings({ configured, currentAppId }: BankingSettingsProps) {
  const t = useT()
  const [appId, setAppId] = useState(currentAppId ?? '')
  const [keyPath, setKeyPath] = useState('')
  const [publicKey, setPublicKey] = useState<string | null>(null)
  const [generating, setGenerating] = useState(false)
  const [copied, setCopied] = useState(false)
  const [saving, setSaving] = useState(false)
  const [status, setStatus] = useState<'idle' | 'saved' | 'error'>('idle')
  const [error, setError] = useState<string | null>(null)

  async function handleGenerate() {
    setError(null)
    setGenerating(true)
    try {
      const res = await window.florin?.generateEbKey?.()
      if (!res) throw new Error(t('banking.generateFailed', 'Key generation failed.'))
      setKeyPath(res.keyPath)
      setPublicKey(res.publicKey)
    } catch (err) {
      setError(err instanceof Error ? err.message : t('banking.generateFailed', 'Key generation failed.'))
    } finally {
      setGenerating(false)
    }
  }

  async function handleCopyPublicKey() {
    if (!publicKey) return
    try {
      await navigator.clipboard.writeText(publicKey)
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    } catch {
      // Clipboard denied — the textarea is selectable as a fallback.
    }
  }

  async function handlePickPem() {
    const dest = await window.florin?.importPem?.()
    if (dest) {
      setKeyPath(dest)
      setPublicKey(null)
    }
  }

  async function handleSave() {
    if (!appId.trim() || !keyPath.trim()) {
      setError(t('banking.credentialsRequired', 'Both App ID and private key are required.'))
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
      if (!data.success) throw new Error(data.error || t('banking.failedToSave', 'Failed to save'))
      setStatus('saved')
      setTimeout(() => setStatus('idle'), 3000)
    } catch (err) {
      setError(err instanceof Error ? err.message : t('banking.failedToSave', 'Failed to save'))
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
          <span>{t('banking.apiConfigured', 'Banking API configured')}</span>
        </div>
      )}

      <div className="rounded-md border border-border bg-muted/30 p-3 text-xs text-muted-foreground">
        <strong className="text-foreground">Enable Banking (PSD2)</strong> —{' '}
        {t('banking.psd2Intro', 'connect to EU banks to auto-import transactions. Your API credentials stay on this machine. Get credentials at')}{' '}
        <a
          href="https://enablebanking.com"
          target="_blank"
          rel="noopener noreferrer"
          className="text-primary hover:underline"
        >
          enablebanking.com
        </a>
        <span className="mt-2 block">
          {t('banking.redirectHint', 'In your Enable Banking application, add this redirect URI:')}
        </span>
        <code className="mt-1 block break-all rounded bg-background px-2 py-1 text-[11px] text-foreground">
          {REDIRECT_URI}
        </code>
      </div>

      <div className="space-y-3">
        <div className="space-y-1.5">
          <label htmlFor="eb-app-id" className="text-xs font-medium">
            {t('banking.appIdLabel', 'App ID')}
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

        <div className="space-y-2">
          <label className="text-xs font-medium">{t('banking.privateKeyLabel', 'RSA key')}</label>

          {/* Recommended: generate the key pair in-app — no terminal. */}
          <button
            type="button"
            onClick={handleGenerate}
            disabled={generating}
            className="inline-flex items-center gap-2 rounded-md bg-primary px-3 py-2 text-sm font-medium text-primary-foreground shadow-sm transition-colors hover:bg-primary/90 disabled:opacity-50"
          >
            <KeyRound className="h-3.5 w-3.5" />
            {generating
              ? t('banking.generating', 'Generating…')
              : t('banking.generateKey', 'Generate a key')}
          </button>
          <p className="text-[11px] text-muted-foreground">
            {t('banking.generateHint', 'No terminal needed — the private key is created and stored on this machine; only the public key is shared.')}
          </p>

          {publicKey && (
            <div className="space-y-2 rounded-md border border-emerald-500/40 bg-emerald-500/5 p-3">
              <p className="text-xs font-medium text-emerald-600 dark:text-emerald-400">
                {t('banking.keyGenerated', 'Key generated — paste the public key into your Enable Banking application:')}
              </p>
              <textarea
                readOnly
                value={publicKey}
                rows={5}
                onFocus={(e) => e.currentTarget.select()}
                className="w-full resize-none rounded border border-input bg-background px-2 py-1.5 font-mono text-[10px] leading-tight text-foreground focus:outline-none focus:ring-2 focus:ring-ring"
              />
              <button
                type="button"
                onClick={handleCopyPublicKey}
                className="inline-flex items-center gap-2 rounded-md border border-input bg-background px-3 py-1.5 text-xs shadow-sm hover:bg-accent hover:text-accent-foreground"
              >
                <Copy className="h-3.5 w-3.5" />
                {copied ? t('banking.copied', 'Copied ✓') : t('banking.copyPublicKey', 'Copy public key')}
              </button>
            </div>
          )}

          {/* Advanced: reuse an existing key (e.g. shared with a self-hosted web instance). */}
          <details className="text-xs text-muted-foreground">
            <summary className="cursor-pointer select-none hover:text-foreground">
              {t('banking.orImportExisting', 'or import an existing .pem key')}
            </summary>
            <div className="mt-2 flex items-center gap-2">
              <button
                type="button"
                onClick={handlePickPem}
                className="inline-flex items-center gap-2 rounded-md border border-input bg-background px-3 py-2 text-sm shadow-sm hover:bg-accent hover:text-accent-foreground"
              >
                <FileKey className="h-3.5 w-3.5" />
                {keyPath && !publicKey
                  ? t('banking.changeFile', 'Change file…')
                  : t('banking.importPem', 'Import .pem file…')}
              </button>
              {keyPath && !publicKey && (
                <span className="truncate text-xs text-muted-foreground">{keyPath.split('/').pop()}</span>
              )}
            </div>
          </details>

          {!keyPath && configured && (
            <p className="text-[11px] text-muted-foreground">
              {t('banking.keyAlreadyImported', 'A key is already configured. Generate or import a new one only to replace it.')}
            </p>
          )}
        </div>
      </div>

      {error && <p className="text-xs text-destructive">{error}</p>}
      {status === 'saved' && (
        <p className="text-xs text-emerald-600 dark:text-emerald-400">
          {t('banking.savedMessage', 'Saved. You can now connect bank accounts from the Accounts page.')}
        </p>
      )}

      <button
        type="button"
        onClick={handleSave}
        disabled={saving}
        className="inline-flex items-center gap-2 rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground shadow-sm transition-colors hover:bg-primary/90 disabled:opacity-50"
      >
        <Unplug className="h-3.5 w-3.5" />
        {saving
          ? t('banking.saving', 'Saving…')
          : configured
            ? t('banking.updateCredentials', 'Update Credentials')
            : t('banking.configureBanking', 'Configure Banking')}
      </button>
    </div>
  )
}
