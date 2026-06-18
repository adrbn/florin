'use client'

import { useState } from 'react'
import type { CreateAccountInput, ActionResult } from '../../../../types/index'
import { useT } from '../../../../i18n/context'

interface FirstAccountStepProps {
  onCreateAccount: (input: CreateAccountInput) => Promise<ActionResult<unknown>>
}

const ACCOUNT_TYPES = [
  { value: 'checking', labelKey: 'onboarding.accountType.checking', fallback: 'Checking' },
  { value: 'savings', labelKey: 'onboarding.accountType.savings', fallback: 'Savings' },
  { value: 'cash', labelKey: 'onboarding.accountType.cash', fallback: 'Cash' },
  { value: 'broker_cash', labelKey: 'onboarding.accountType.brokerCash', fallback: 'Brokerage (cash)' },
  {
    value: 'broker_portfolio',
    labelKey: 'onboarding.accountType.brokerPortfolio',
    fallback: 'Brokerage (portfolio)',
  },
  { value: 'loan', labelKey: 'onboarding.accountType.loan', fallback: 'Loan' },
  { value: 'other', labelKey: 'onboarding.accountType.other', fallback: 'Other' },
]

export function FirstAccountStep({ onCreateAccount }: FirstAccountStepProps) {
  const t = useT()
  const [name, setName] = useState('')
  const [kind, setKind] = useState('checking')
  const [balance, setBalance] = useState('')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function handleCreate() {
    if (!name.trim()) {
      setError(t('onboarding.account.nameRequired', 'Account name is required.'))
      return
    }
    const trimmedBalance = balance.trim().replace(',', '.')
    const parsedBalance = trimmedBalance === '' ? 0 : parseFloat(trimmedBalance)
    if (Number.isNaN(parsedBalance)) {
      setError(t('onboarding.account.balanceNumber', 'Starting balance must be a number.'))
      return
    }
    setSaving(true)
    setError(null)
    try {
      const result = await onCreateAccount({
        name: name.trim(),
        kind,
        currentBalance: parsedBalance,
      })
      if (!result.success) {
        setError(result.error ?? t('onboarding.account.createError', 'Failed to create account'))
      }
    } catch (err) {
      setError(
        err instanceof Error
          ? err.message
          : t('onboarding.account.createError', 'Failed to create account'),
      )
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="space-y-6">
      <div className="space-y-1">
        <h2 className="text-xl font-semibold">
          {t('onboarding.account.heading', 'Create Your First Account')}
        </h2>
        <p className="text-sm text-muted-foreground">
          {t(
            'onboarding.account.body',
            "Add a checking account, savings account, cash — anything you'd like to track. You can add more later.",
          )}
        </p>
      </div>

      <div className="space-y-4">
        <div className="space-y-1.5">
          <label htmlFor="account-name" className="text-sm font-medium">
            {t('onboarding.account.nameLabel', 'Account Name')}
          </label>
          <input
            id="account-name"
            type="text"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder={t('onboarding.account.namePlaceholder', 'e.g. Main Checking')}
            className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm shadow-sm placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-ring"
          />
        </div>

        <div className="space-y-1.5">
          <label htmlFor="account-type" className="text-sm font-medium">
            {t('onboarding.account.typeLabel', 'Account Type')}
          </label>
          <select
            id="account-type"
            value={kind}
            onChange={(e) => setKind(e.target.value)}
            className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm shadow-sm focus:outline-none focus:ring-2 focus:ring-ring"
          >
            {ACCOUNT_TYPES.map((tp) => (
              <option key={tp.value} value={tp.value}>
                {t(tp.labelKey, tp.fallback)}
              </option>
            ))}
          </select>
        </div>

        <div className="space-y-1.5">
          <label htmlFor="starting-balance" className="text-sm font-medium">
            {t('onboarding.account.balanceLabel', 'Starting Balance')}
          </label>
          <input
            id="starting-balance"
            type="number"
            value={balance}
            onChange={(e) => setBalance(e.target.value)}
            placeholder="0.00"
            step="0.01"
            className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm shadow-sm focus:outline-none focus:ring-2 focus:ring-ring"
          />
        </div>
      </div>

      {error && <p className="text-sm text-destructive">{error}</p>}

      <button
        type="button"
        onClick={handleCreate}
        disabled={saving}
        className="w-full rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground transition-colors hover:bg-primary/90 disabled:opacity-50"
      >
        {saving
          ? t('onboarding.account.creating', 'Creating…')
          : t('onboarding.account.create', 'Create Account')}
      </button>
    </div>
  )
}
