'use client'

import { useState } from 'react'
import { useT } from '../../../../i18n/context'
import { SUPPORTED_LOCALES } from '../../../../i18n'

interface LocalePickerStepProps {
  onSave: (locale: string, currency: string) => Promise<void>
}

const LANGUAGE_OPTIONS = SUPPORTED_LOCALES.map((l) => ({ value: l.code, label: l.name }))

const CURRENCY_OPTIONS = [
  { value: 'EUR', label: 'EUR — Euro' },
  { value: 'GBP', label: 'GBP — British Pound' },
  { value: 'USD', label: 'USD — US Dollar' },
  { value: 'CHF', label: 'CHF — Swiss Franc' },
]

export function LocalePickerStep({ onSave }: LocalePickerStepProps) {
  const t = useT()
  const [locale, setLocale] = useState('en')
  const [currency, setCurrency] = useState('EUR')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function handleSave() {
    setSaving(true)
    setError(null)
    try {
      await onSave(locale, currency)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save preferences')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="space-y-6">
      <div className="space-y-1">
        <h2 className="text-xl font-semibold">
          {t('onboarding.locale.title', 'Language & Currency')}
        </h2>
        <p className="text-sm text-muted-foreground">
          {t(
            'onboarding.locale.hint',
            'These preferences affect how dates, numbers, and categories are displayed.',
          )}
        </p>
      </div>

      <div className="space-y-4">
        <div className="space-y-1.5">
          <label htmlFor="locale-select" className="text-sm font-medium">
            {t('onboarding.locale.languageLabel', 'Language')}
          </label>
          <select
            id="locale-select"
            value={locale}
            onChange={(e) => setLocale(e.target.value)}
            className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm shadow-sm focus:outline-none focus:ring-2 focus:ring-ring"
          >
            {LANGUAGE_OPTIONS.map((opt) => (
              <option key={opt.value} value={opt.value}>
                {opt.label}
              </option>
            ))}
          </select>
        </div>

        <div className="space-y-1.5">
          <label htmlFor="currency-select" className="text-sm font-medium">
            {t('onboarding.locale.currencyLabel', 'Currency')}
          </label>
          <select
            id="currency-select"
            value={currency}
            onChange={(e) => setCurrency(e.target.value)}
            className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm shadow-sm focus:outline-none focus:ring-2 focus:ring-ring"
          >
            {CURRENCY_OPTIONS.map((opt) => (
              <option key={opt.value} value={opt.value}>
                {opt.label}
              </option>
            ))}
          </select>
        </div>
      </div>

      {error && <p className="text-sm text-destructive">{error}</p>}

      <button
        type="button"
        onClick={handleSave}
        disabled={saving}
        className="w-full rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground transition-colors hover:bg-primary/90 disabled:opacity-50"
      >
        {saving
          ? t('onboarding.saving', 'Saving…')
          : t('onboarding.saveContinue', 'Save & Continue')}
      </button>
    </div>
  )
}
