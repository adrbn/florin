'use client'

import { createContext, useContext, useMemo } from 'react'
import type { TFunction } from '../../../i18n'
import { createV2T } from './index'

interface V2I18nValue {
  t: TFunction
  locale: string
}

const V2I18nContext = createContext<V2I18nValue>({ t: createV2T('en'), locale: 'en' })

export function V2I18nProvider({
  locale,
  children,
}: {
  locale: string
  children: React.ReactNode
}) {
  const value = useMemo(() => ({ t: createV2T(locale), locale }), [locale])
  return <V2I18nContext.Provider value={value}>{children}</V2I18nContext.Provider>
}

export function useV2T(): TFunction {
  return useContext(V2I18nContext).t
}

export function useV2Locale(): string {
  return useContext(V2I18nContext).locale
}
