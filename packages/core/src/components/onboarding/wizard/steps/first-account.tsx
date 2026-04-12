'use client'

import { useState } from 'react'
import type { CreateAccountInput, ActionResult } from '../../../../types/index.js'

interface FirstAccountStepProps {
  onCreateAccount: (input: CreateAccountInput) => Promise<ActionResult>
}

const ACCOUNT_TYPES = [
  { value: 'checking', label: 'Checking' },
  { value: 'savings', label: 'Savings' },
  { value: 'cash', label: 'Cash' },
  { value: 'broker_cash', label: 'Brokerage (cash)' },
  { value: 'broker_portfolio', label: 'Brokerage (portfolio)' },
  { value: 'loan', label: 'Loan' },
  { value: 'other', label: 'Other' },
]

export function FirstAccountStep({ onCreateAccount }: FirstAccountStepProps) {
  const [name, setName] = useState('')
  const [kind, setKind] = useState('checking')
  const [balance, setBalance] = useState('0')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function handleCreate() {
    if (!name.trim()) {
      setError('Account name is required.')
      return
    }
    const parsedBalance = parseFloat(balance)
    if (Number.isNaN(parsedBalance)) {
      setError('Starting balance must be a number.')
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
        setError(result.error ?? 'Failed to create account')
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to create account')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="space-y-6">
      <div className="space-y-1">
        <h2 className="text-xl font-semibold">Create Your First Account</h2>
        <p className="text-sm text-muted-foreground">
          Add a checking account, savings account, cash — anything you'd like to track. You can add
          more later.
        </p>
      </div>

      <div className="space-y-4">
        <div className="space-y-1.5">
          <label htmlFor="account-name" className="text-sm font-medium">
            Account Name
          </label>
          <input
            id="account-name"
            type="text"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="e.g. Main Checking"
            className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm shadow-sm placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-ring"
          />
        </div>

        <div className="space-y-1.5">
          <label htmlFor="account-type" className="text-sm font-medium">
            Account Type
          </label>
          <select
            id="account-type"
            value={kind}
            onChange={(e) => setKind(e.target.value)}
            className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm shadow-sm focus:outline-none focus:ring-2 focus:ring-ring"
          >
            {ACCOUNT_TYPES.map((t) => (
              <option key={t.value} value={t.value}>
                {t.label}
              </option>
            ))}
          </select>
        </div>

        <div className="space-y-1.5">
          <label htmlFor="starting-balance" className="text-sm font-medium">
            Starting Balance
          </label>
          <input
            id="starting-balance"
            type="number"
            value={balance}
            onChange={(e) => setBalance(e.target.value)}
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
        {saving ? 'Creating…' : 'Create Account'}
      </button>
    </div>
  )
}
