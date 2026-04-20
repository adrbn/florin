'use client'

import { Plus } from 'lucide-react'
import { useState } from 'react'
import { AccountForm } from '../accounts/account-form'
import { Button } from '../ui/button'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '../ui/dialog'
import { useT } from '../../i18n/context'
import type { ActionResult, CreateAccountInput, UpdateAccountInput } from '../../types/index'

interface AddAccountCardProps {
  onCreateAccount: (input: CreateAccountInput) => Promise<ActionResult<{ id: string }>>
  onUpdateAccount: (input: UpdateAccountInput) => Promise<ActionResult>
}

export function AddAccountCard({ onCreateAccount, onUpdateAccount }: AddAccountCardProps) {
  const t = useT()
  const [open, setOpen] = useState(false)
  const newAccountLabel = t('accounts.newAccount', 'New account')

  return (
    <>
      <Button variant="outline" className="w-full" onClick={() => setOpen(true)}>
        <Plus className="mr-2 h-4 w-4" />
        {newAccountLabel}
      </Button>
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>{newAccountLabel}</DialogTitle>
          </DialogHeader>
          <AccountForm
            onSuccess={() => setOpen(false)}
            onCreateAccount={onCreateAccount}
            onUpdateAccount={onUpdateAccount}
          />
        </DialogContent>
      </Dialog>
    </>
  )
}
