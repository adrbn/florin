'use client'

import { Plus, X } from 'lucide-react'
import { useState } from 'react'
import { AccountForm } from '../accounts/account-form'
import { Button } from '../ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '../ui/card'
import type { ActionResult, CreateAccountInput, UpdateAccountInput } from '../../types/index'

interface AddAccountCardProps {
  onCreateAccount: (input: CreateAccountInput) => Promise<ActionResult<{ id: string }>>
  onUpdateAccount: (input: UpdateAccountInput) => Promise<ActionResult>
}

/**
 * Collapsible "New account" card. The full form is heavy (kind picker, icon
 * picker, color picker, starting balance) and takes a lot of vertical space,
 * so we hide it behind a single "+ New account" button until the user
 * actually wants to create one. The form auto-collapses on success.
 */
export function AddAccountCard({ onCreateAccount, onUpdateAccount }: AddAccountCardProps) {
  const [open, setOpen] = useState(false)

  if (!open) {
    return (
      <Button variant="outline" className="w-full" onClick={() => setOpen(true)}>
        <Plus className="mr-2 h-4 w-4" />
        New account
      </Button>
    )
  }

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
        <CardTitle>New account</CardTitle>
        <Button
          variant="ghost"
          size="icon"
          aria-label="Close"
          onClick={() => setOpen(false)}
        >
          <X className="h-4 w-4" />
        </Button>
      </CardHeader>
      <CardContent>
        <AccountForm onSuccess={() => setOpen(false)} onCreateAccount={onCreateAccount} onUpdateAccount={onUpdateAccount} />
      </CardContent>
    </Card>
  )
}
