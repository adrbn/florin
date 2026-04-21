'use client'

import { useRouter } from 'next/navigation'
import { AccountForm, type AccountFormInitial } from '@florin/core/components/accounts/account-form'
import type {
  ActionResult,
  CreateAccountInput,
  UpdateAccountInput,
} from '@florin/core/types'

interface Props {
  initial: AccountFormInitial
  onCreateAccount: (input: CreateAccountInput) => Promise<ActionResult<{ id: string }>>
  onUpdateAccount: (input: UpdateAccountInput) => Promise<ActionResult>
  /** Route to return to after a successful save. */
  returnHref: string
}

/**
 * Client wrapper around AccountForm that navigates back to the account
 * detail page once the server action succeeds.
 */
export function AccountEditFormClient({
  initial,
  onCreateAccount,
  onUpdateAccount,
  returnHref,
}: Props) {
  const router = useRouter()
  return (
    <AccountForm
      initial={initial}
      onCreateAccount={onCreateAccount}
      onUpdateAccount={onUpdateAccount}
      onSuccess={() => router.push(returnHref as never)}
    />
  )
}
