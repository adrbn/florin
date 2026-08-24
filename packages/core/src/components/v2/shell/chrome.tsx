'use client'

import { createContext, useContext, useMemo, useState } from 'react'
import type { V2Account, V2AddActions, V2Category } from '../types'
import { QuickAddSheet } from './quick-add-sheet'
import { ProfileSheet } from './profile-sheet'
import { V2TabBar } from './tab-bar'

interface ChromeValue {
  openQuickAdd: () => void
  openProfile: () => void
  reviewCount: number
  /** True when a native shell already supplies the tab bar and the header. */
  chromeless: boolean
}

const ChromeContext = createContext<ChromeValue>({
  openQuickAdd: () => {},
  openProfile: () => {},
  reviewCount: 0,
  chromeless: false,
})

export function useV2Chrome(): ChromeValue {
  return useContext(ChromeContext)
}

export interface V2ChromeProps {
  accounts: V2Account[]
  categories: V2Category[]
  reviewCount: number
  actions: V2AddActions
  version: string
  /**
   * Drop the floating tab bar and the profile avatar because the host app
   * already draws them natively. Two tab bars stacked is the giveaway that a
   * "native" app is a web page in a jacket.
   */
  chromeless?: boolean
  /** Where the language picker POSTs: web '/api/locale', desktop '/api/settings/locale'. */
  localeEndpoint?: string
  /** Rendered inside the profile sheet — the app supplies its own sign-out. */
  signOut?: React.ReactNode
  children: React.ReactNode
}

/**
 * Everything that persists across screens: the floating tab bar, the quick-add
 * sheet behind its centre button, and the profile sheet behind the header
 * avatar.
 *
 * Screens reach the two sheets through context rather than props because the
 * profile trigger lives in a per-screen header — threading `onOpenProfile`
 * through fifteen screen components to reach one button is exactly the kind of
 * prop-drilling that makes a shell hard to change later.
 */
export function V2Chrome({
  accounts,
  categories,
  reviewCount,
  actions,
  version,
  chromeless = false,
  localeEndpoint,
  signOut,
  children,
}: V2ChromeProps) {
  const [quickAdd, setQuickAdd] = useState(false)
  const [profile, setProfile] = useState(false)

  const value = useMemo<ChromeValue>(
    () => ({
      openQuickAdd: () => setQuickAdd(true),
      openProfile: () => setProfile(true),
      reviewCount,
      chromeless,
    }),
    [reviewCount, chromeless],
  )

  return (
    <ChromeContext.Provider value={value}>
      {children}
      {!chromeless && <V2TabBar onAdd={() => setQuickAdd(true)} />}
      <QuickAddSheet
        open={quickAdd}
        onClose={() => setQuickAdd(false)}
        accounts={accounts}
        categories={categories}
        actions={actions}
      />
      <ProfileSheet
        open={profile}
        onClose={() => setProfile(false)}
        reviewCount={reviewCount}
        version={version}
        localeEndpoint={localeEndpoint}
        signOut={signOut}
      />
    </ChromeContext.Provider>
  )
}
