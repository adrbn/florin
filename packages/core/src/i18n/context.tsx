'use client'
import { createContext, useContext } from 'react'
import { createT, type TFunction } from './index'

const I18nContext = createContext<TFunction>(createT('en'))

export function I18nProvider({ locale, children }: { locale: string; children: React.ReactNode }) {
  const t = createT(locale)
  return <I18nContext.Provider value={t}>{children}</I18nContext.Provider>
}

export function useT() {
  return useContext(I18nContext)
}
