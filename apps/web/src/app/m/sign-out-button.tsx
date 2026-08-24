'use client'

import { LogOut } from 'lucide-react'
import { signOut } from 'next-auth/react'
import { useV2T } from '@florin/core/components/v2/i18n/context'

/** Web-only: the desktop build has no session to end. */
export function SignOutButton() {
  const t = useV2T()
  return (
    <button
      type="button"
      onClick={() => signOut({ callbackUrl: '/login' })}
      className="v2-btn v2-btn-ghost w-full"
    >
      <LogOut className="h-4 w-4" />
      {t('v2.settings.signOut', 'Sign out')}
    </button>
  )
}
