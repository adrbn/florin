'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { useT } from '@florin/core/i18n/context'

const LOCALES = [
  { value: 'en', label: 'English' },
  { value: 'fr-FR', label: 'Français' },
  { value: 'de-DE', label: 'Deutsch' },
  { value: 'es-ES', label: 'Español' },
  { value: 'it-IT', label: 'Italiano' },
  { value: 'pt-PT', label: 'Português' },
  { value: 'nl-NL', label: 'Nederlands' },
]

const CURRENCIES = [
  { value: 'EUR', label: 'EUR — Euro' },
  { value: 'USD', label: 'USD — US Dollar' },
  { value: 'GBP', label: 'GBP — British Pound' },
  { value: 'CHF', label: 'CHF — Swiss Franc' },
  { value: 'CAD', label: 'CAD — Canadian Dollar' },
  { value: 'AUD', label: 'AUD — Australian Dollar' },
  { value: 'JPY', label: 'JPY — Japanese Yen' },
  { value: 'SEK', label: 'SEK — Swedish Krona' },
  { value: 'NOK', label: 'NOK — Norwegian Krone' },
  { value: 'DKK', label: 'DKK — Danish Krone' },
  { value: 'PLN', label: 'PLN — Polish Zloty' },
  { value: 'CZK', label: 'CZK — Czech Koruna' },
]

interface LocaleSettingsProps {
  currentLocale: string
  currentCurrency: string
}

export function LocaleSettings({ currentLocale, currentCurrency }: LocaleSettingsProps) {
  const router = useRouter()
  const t = useT()
  const [locale, setLocale] = useState(currentLocale)
  const [currency, setCurrency] = useState(currentCurrency)
  const [saving, setSaving] = useState(false)

  async function handleLocaleChange(newLocale: string) {
    setLocale(newLocale)
    setSaving(true)
    try {
      await fetch('/api/settings/locale', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ locale: newLocale }),
      })
      router.refresh()
    } finally {
      setSaving(false)
    }
  }

  async function handleCurrencyChange(newCurrency: string) {
    setCurrency(newCurrency)
    setSaving(true)
    try {
      await fetch('/api/settings/currency', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ currency: newCurrency }),
      })
      router.refresh()
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="space-y-2">
      <div className="flex items-baseline justify-between gap-3 border-b border-border/40 pb-1.5">
        <span className="text-xs uppercase tracking-wide text-muted-foreground">{t('settings.locale', 'Language')}</span>
        <select
          value={locale}
          onChange={(e) => handleLocaleChange(e.target.value)}
          disabled={saving}
          className="rounded-md border border-border bg-background px-2 py-1 text-sm text-foreground"
        >
          {LOCALES.map((l) => (
            <option key={l.value} value={l.value}>{l.label}</option>
          ))}
        </select>
      </div>
      <div className="flex items-baseline justify-between gap-3 border-b border-border/40 pb-1.5">
        <span className="text-xs uppercase tracking-wide text-muted-foreground">{t('settings.baseCurrency', 'Base currency')}</span>
        <select
          value={currency}
          onChange={(e) => handleCurrencyChange(e.target.value)}
          disabled={saving}
          className="rounded-md border border-border bg-background px-2 py-1 text-sm text-foreground"
        >
          {CURRENCIES.map((c) => (
            <option key={c.value} value={c.value}>{c.label}</option>
          ))}
        </select>
      </div>
    </div>
  )
}
