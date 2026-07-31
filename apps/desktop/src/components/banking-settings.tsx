'use client'

import { useState } from 'react'
import { Check, CheckCircle, Copy, ExternalLink, FileKey, KeyRound } from 'lucide-react'
import { useT } from '@florin/core/i18n/context'

interface BankingSettingsProps {
  configured: boolean
  currentAppId: string | null
}

const REDIRECT_URI = 'https://127.0.0.1:3847/api/banking/callback'
const EB_URL = 'https://enablebanking.com'

/** Numbered step bubble — filled once the step is behind you. */
function StepNum({ n, done }: { n: number; done: boolean }) {
  return (
    <span
      className={`flex h-6 w-6 shrink-0 items-center justify-center rounded-full text-xs font-semibold ${
        done
          ? 'bg-emerald-500/15 text-emerald-600 dark:text-emerald-400'
          : 'bg-primary/10 text-primary'
      }`}
    >
      {done ? <Check className="h-3.5 w-3.5" /> : n}
    </span>
  )
}

/**
 * Bank Sync setup. Enable Banking requires the user to register their own free
 * application, which is inherently a few steps — so the job here is to make
 * those steps feel small: three numbered actions in the order you actually do
 * them, one control each, stated up front as a one-time thing. Everything
 * optional (importing an existing key) hides behind a disclosure, and once it
 * is set up the whole thing collapses to a single line so a configured user
 * never sees the wizard again.
 */
export function BankingSettings({ configured, currentAppId }: BankingSettingsProps) {
  const t = useT()
  const [appId, setAppId] = useState(currentAppId ?? '')
  const [keyPath, setKeyPath] = useState('')
  const [publicKey, setPublicKey] = useState<string | null>(null)
  const [generating, setGenerating] = useState(false)
  const [copied, setCopied] = useState<'key' | 'uri' | null>(null)
  const [saving, setSaving] = useState(false)
  const [status, setStatus] = useState<'idle' | 'saved' | 'error'>('idle')
  const [error, setError] = useState<string | null>(null)
  // A configured user sees a one-line summary until they ask to change it.
  const [editing, setEditing] = useState(false)

  const keyReady = Boolean(publicKey) || Boolean(keyPath)

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

  async function copy(text: string, which: 'key' | 'uri') {
    try {
      await navigator.clipboard.writeText(text)
      setCopied(which)
      setTimeout(() => setCopied(null), 2000)
    } catch {
      // Clipboard denied — the field stays selectable as a fallback.
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
      setEditing(false)
      setTimeout(() => setStatus('idle'), 3000)
    } catch (err) {
      setError(err instanceof Error ? err.message : t('banking.failedToSave', 'Failed to save'))
      setStatus('error')
    } finally {
      setSaving(false)
    }
  }

  // ---- Already set up: one line, nothing else. ----
  if (configured && !editing) {
    return (
      <div className="space-y-3 text-sm">
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-md border border-emerald-500/40 bg-emerald-500/5 px-3 py-2.5">
          <span className="flex items-center gap-2 text-emerald-600 dark:text-emerald-400">
            <CheckCircle className="h-4 w-4 shrink-0" />
            <span className="font-medium">{t('banking.connected', 'Bank connection ready')}</span>
          </span>
          <button
            type="button"
            onClick={() => setEditing(true)}
            className="text-xs text-muted-foreground underline-offset-2 transition-colors hover:text-foreground hover:underline"
          >
            {t('banking.reconfigure', 'Reconfigure')}
          </button>
        </div>
        {status === 'saved' && (
          <p className="text-xs text-emerald-600 dark:text-emerald-400">
            {t('banking.savedMessage', 'Saved. You can now connect bank accounts from the Accounts page.')}
          </p>
        )}
      </div>
    )
  }

  // ---- Setup: three numbered steps. ----
  return (
    <div className="space-y-4 text-sm">
      <div>
        <p className="font-medium text-foreground">
          {t('banking.setupTitle', 'Connect your bank')}
        </p>
        <p className="mt-0.5 text-xs text-muted-foreground">
          {t(
            'banking.setupIntro',
            'A one-time setup, about 2 minutes. Everything stays on this machine.',
          )}
        </p>
      </div>

      <ol className="space-y-4">
        {/* 1 — key */}
        <li className="flex gap-3">
          <StepNum n={1} done={keyReady} />
          <div className="min-w-0 flex-1 space-y-2">
            <p className="text-xs font-medium text-foreground">
              {t('banking.step1', 'Create your key')}
            </p>
            {publicKey ? (
              <div className="space-y-2">
                <textarea
                  readOnly
                  value={publicKey}
                  rows={3}
                  onFocus={(e) => e.currentTarget.select()}
                  className="w-full resize-none rounded-md border border-input bg-background px-2 py-1.5 font-mono text-[10px] leading-tight focus:outline-none focus:ring-2 focus:ring-ring"
                />
                <button
                  type="button"
                  onClick={() => copy(publicKey, 'key')}
                  className="inline-flex items-center gap-2 rounded-md border border-input bg-background px-3 py-1.5 text-xs shadow-sm transition-colors hover:bg-accent"
                >
                  <Copy className="h-3.5 w-3.5" />
                  {copied === 'key'
                    ? t('banking.copied', 'Copied ✓')
                    : t('banking.copyPublicKey', 'Copy public key')}
                </button>
              </div>
            ) : (
              <button
                type="button"
                onClick={handleGenerate}
                disabled={generating}
                className="inline-flex items-center gap-2 rounded-md bg-primary px-3 py-2 text-sm font-medium text-primary-foreground shadow-sm transition-colors hover:bg-primary/90 disabled:opacity-50"
              >
                <KeyRound className="h-3.5 w-3.5" />
                {generating ? t('banking.generating', 'Generating…') : t('banking.generateKey', 'Generate my key')}
              </button>
            )}
          </div>
        </li>

        {/* 2 — register the app */}
        <li className={`flex gap-3 ${keyReady ? '' : 'opacity-50'}`}>
          <StepNum n={2} done={false} />
          <div className="min-w-0 flex-1 space-y-2">
            <p className="text-xs font-medium text-foreground">
              {t('banking.step2', 'Create your free Enable Banking app')}
            </p>
            <p className="text-[11px] text-muted-foreground">
              {t('banking.step2Body', 'Paste the key you just copied into it, then add this redirect address:')}
            </p>
            <div className="flex items-center gap-2">
              <code className="min-w-0 flex-1 truncate rounded bg-muted px-2 py-1.5 text-[11px]">
                {REDIRECT_URI}
              </code>
              <button
                type="button"
                onClick={() => copy(REDIRECT_URI, 'uri')}
                className="inline-flex shrink-0 items-center gap-1.5 rounded-md border border-input bg-background px-2.5 py-1.5 text-xs shadow-sm transition-colors hover:bg-accent"
              >
                <Copy className="h-3.5 w-3.5" />
                {copied === 'uri' ? t('banking.copied', 'Copied ✓') : t('common.copy', 'Copy')}
              </button>
            </div>
            <a
              href={EB_URL}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-1.5 text-xs text-primary hover:underline"
            >
              <ExternalLink className="h-3.5 w-3.5" />
              {t('banking.openEnableBanking', 'Open enablebanking.com')}
            </a>
          </div>
        </li>

        {/* 3 — app id */}
        <li className={`flex gap-3 ${keyReady ? '' : 'opacity-50'}`}>
          <StepNum n={3} done={false} />
          <div className="min-w-0 flex-1 space-y-2">
            <p className="text-xs font-medium text-foreground">
              {t('banking.step3', 'Paste your App ID here')}
            </p>
            <input
              id="eb-app-id"
              type="text"
              value={appId}
              onChange={(e) => setAppId(e.target.value)}
              placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
              className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm shadow-sm placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-ring"
            />
          </div>
        </li>
      </ol>

      {error && <p className="text-xs text-destructive">{error}</p>}

      <div className="flex flex-wrap items-center gap-3">
        <button
          type="button"
          onClick={handleSave}
          disabled={saving || !appId.trim() || !keyPath.trim()}
          className="inline-flex items-center gap-2 rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground shadow-sm transition-colors hover:bg-primary/90 disabled:opacity-50"
        >
          {saving ? t('banking.saving', 'Saving…') : t('common.save', 'Save')}
        </button>
        {configured && (
          <button
            type="button"
            onClick={() => setEditing(false)}
            className="text-xs text-muted-foreground underline-offset-2 hover:text-foreground hover:underline"
          >
            {t('common.cancel', 'Cancel')}
          </button>
        )}
      </div>

      {/* Advanced: reuse a key you already have (e.g. from a self-hosted web instance). */}
      <details className="text-xs text-muted-foreground">
        <summary className="cursor-pointer select-none hover:text-foreground">
          {t('banking.orImportExisting', 'or import an existing .pem key')}
        </summary>
        <div className="mt-2 flex flex-wrap items-center gap-2">
          <button
            type="button"
            onClick={handlePickPem}
            className="inline-flex items-center gap-2 rounded-md border border-input bg-background px-3 py-2 text-sm shadow-sm transition-colors hover:bg-accent"
          >
            <FileKey className="h-3.5 w-3.5" />
            {t('banking.importPem', 'Import .pem file…')}
          </button>
          {keyPath && !publicKey && (
            <span className="truncate text-xs">{keyPath.split('/').pop()}</span>
          )}
        </div>
      </details>
    </div>
  )
}
