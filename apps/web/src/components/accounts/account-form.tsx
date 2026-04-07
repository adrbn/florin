'use client'

import { useState, useTransition } from 'react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { type CreateAccountInput, createAccount } from '@/server/actions/accounts'

const KINDS: ReadonlyArray<{ value: CreateAccountInput['kind']; label: string }> = [
  { value: 'checking', label: 'Checking' },
  { value: 'savings', label: 'Savings' },
  { value: 'cash', label: 'Cash' },
  { value: 'loan', label: 'Loan' },
  { value: 'broker_cash', label: 'Broker (cash)' },
  { value: 'broker_portfolio', label: 'Broker (portfolio)' },
  { value: 'other', label: 'Other' },
]

interface AccountFormProps {
  onSuccess?: () => void
}

export function AccountForm({ onSuccess }: AccountFormProps) {
  const [pending, startTransition] = useTransition()
  const [error, setError] = useState<string | null>(null)

  const onSubmit = (formData: FormData) => {
    setError(null)
    const input: CreateAccountInput = {
      name: String(formData.get('name') ?? ''),
      kind: formData.get('kind') as CreateAccountInput['kind'],
      institution: String(formData.get('institution') ?? '') || null,
      currentBalance: Number(formData.get('currentBalance') ?? 0),
      displayIcon: String(formData.get('displayIcon') ?? '') || null,
      displayColor: String(formData.get('displayColor') ?? '') || null,
    }

    startTransition(async () => {
      const result = await createAccount(input)
      if (!result.success) {
        setError(result.error ?? 'Unknown error')
        return
      }
      onSuccess?.()
      const form = document.getElementById('account-form') as HTMLFormElement | null
      form?.reset()
    })
  }

  return (
    <form id="account-form" action={onSubmit} className="space-y-4">
      <div className="space-y-2">
        <Label htmlFor="name">Name</Label>
        <Input id="name" name="name" required maxLength={100} />
      </div>

      <div className="space-y-2">
        <Label htmlFor="kind">Kind</Label>
        <select
          id="kind"
          name="kind"
          required
          defaultValue="checking"
          className="flex h-9 w-full rounded-md border border-input bg-transparent px-3 py-1 text-sm shadow-sm focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring"
        >
          {KINDS.map((k) => (
            <option key={k.value} value={k.value}>
              {k.label}
            </option>
          ))}
        </select>
      </div>

      <div className="space-y-2">
        <Label htmlFor="institution">Institution</Label>
        <Input id="institution" name="institution" maxLength={100} />
      </div>

      <div className="space-y-2">
        <Label htmlFor="currentBalance">Starting balance (EUR)</Label>
        <Input
          id="currentBalance"
          name="currentBalance"
          type="number"
          step="0.01"
          defaultValue="0"
          required
        />
      </div>

      <div className="grid grid-cols-2 gap-4">
        <div className="space-y-2">
          <Label htmlFor="displayIcon">Icon (emoji)</Label>
          <Input id="displayIcon" name="displayIcon" maxLength={4} placeholder="🏦" />
        </div>
        <div className="space-y-2">
          <Label htmlFor="displayColor">Color (hex)</Label>
          <Input id="displayColor" name="displayColor" maxLength={16} placeholder="#3b82f6" />
        </div>
      </div>

      {error && <p className="text-sm text-destructive">{error}</p>}

      <Button type="submit" disabled={pending} className="w-full">
        {pending ? 'Creating…' : 'Create account'}
      </Button>
    </form>
  )
}
