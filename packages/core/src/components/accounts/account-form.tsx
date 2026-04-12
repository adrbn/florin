'use client'

import { useId, useState, useTransition } from 'react'
import { IconPicker } from '../accounts/icon-picker'
import { Button } from '../ui/button'
import { Input } from '../ui/input'
import { Label } from '../ui/label'
import type { ActionResult, CreateAccountInput, UpdateAccountInput } from '../../types/index'

const KINDS: ReadonlyArray<{ value: CreateAccountInput['kind']; label: string }> = [
  { value: 'checking', label: 'Checking' },
  { value: 'savings', label: 'Savings' },
  { value: 'cash', label: 'Cash' },
  { value: 'loan', label: 'Loan' },
  { value: 'broker_cash', label: 'Broker (cash)' },
  { value: 'broker_portfolio', label: 'Broker (portfolio)' },
  { value: 'other', label: 'Other' },
]

export interface AccountFormInitial {
  id: string
  name: string
  kind: CreateAccountInput['kind']
  institution: string | null
  currentBalance: string | number
  displayIcon: string | null
  displayColor: string | null
  isIncludedInNetWorth: boolean
}

interface AccountFormProps {
  initial?: AccountFormInitial
  onSuccess?: () => void
  onCreateAccount: (input: CreateAccountInput) => Promise<ActionResult<{ id: string }>>
  onUpdateAccount: (input: UpdateAccountInput) => Promise<ActionResult>
}

export function AccountForm({ initial, onSuccess, onCreateAccount, onUpdateAccount }: AccountFormProps) {
  const [pending, startTransition] = useTransition()
  const [error, setError] = useState<string | null>(null)
  const formId = useId()
  const isEdit = Boolean(initial)

  const onSubmit = (formData: FormData) => {
    setError(null)
    const base: CreateAccountInput = {
      name: String(formData.get('name') ?? ''),
      kind: formData.get('kind') as CreateAccountInput['kind'],
      institution: String(formData.get('institution') ?? '') || null,
      currentBalance: Number(formData.get('currentBalance') ?? 0),
      displayIcon: String(formData.get('displayIcon') ?? '') || null,
      displayColor: String(formData.get('displayColor') ?? '') || null,
    }

    startTransition(async () => {
      const result = initial
        ? await onUpdateAccount({
            ...base,
            id: initial.id,
            isIncludedInNetWorth: formData.get('isIncludedInNetWorth') === 'on',
          })
        : await onCreateAccount(base)
      if (!result.success) {
        setError(result.error ?? 'Unknown error')
        return
      }
      onSuccess?.()
      if (!isEdit) {
        const form = document.getElementById(formId) as HTMLFormElement | null
        form?.reset()
      }
    })
  }

  return (
    <form id={formId} action={onSubmit} className="space-y-4">
      <div className="space-y-2">
        <Label htmlFor={`${formId}-name`}>Name</Label>
        <Input
          id={`${formId}-name`}
          name="name"
          required
          maxLength={100}
          defaultValue={initial?.name ?? ''}
        />
      </div>

      <div className="space-y-2">
        <Label htmlFor={`${formId}-kind`}>Kind</Label>
        <select
          id={`${formId}-kind`}
          name="kind"
          required
          defaultValue={initial?.kind ?? 'checking'}
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
        <Label htmlFor={`${formId}-institution`}>Institution</Label>
        <Input
          id={`${formId}-institution`}
          name="institution"
          maxLength={100}
          defaultValue={initial?.institution ?? ''}
          placeholder="e.g. La Banque Postale"
        />
      </div>

      <div className="space-y-2">
        <Label htmlFor={`${formId}-currentBalance`}>
          {isEdit ? 'Current balance (EUR)' : 'Starting balance (EUR)'}
        </Label>
        <Input
          id={`${formId}-currentBalance`}
          name="currentBalance"
          type="number"
          step="0.01"
          defaultValue={initial?.currentBalance ?? '0'}
          required
        />
      </div>

      <IconPicker
        iconName="displayIcon"
        iconValue={initial?.displayIcon ?? null}
        colorName="displayColor"
        colorValue={initial?.displayColor ?? null}
      />

      {isEdit && (
        <div className="flex items-center gap-2">
          <input
            id={`${formId}-included`}
            type="checkbox"
            name="isIncludedInNetWorth"
            defaultChecked={initial?.isIncludedInNetWorth ?? true}
            className="h-4 w-4 rounded border-input"
          />
          <Label htmlFor={`${formId}-included`} className="font-normal">
            Include in net worth
          </Label>
        </div>
      )}

      {error && <p className="text-sm text-destructive">{error}</p>}

      <Button type="submit" disabled={pending} className="w-full">
        {pending ? (isEdit ? 'Saving…' : 'Creating…') : isEdit ? 'Save changes' : 'Create account'}
      </Button>
    </form>
  )
}
