'use client'
import { createContext, useContext } from 'react'
import { createT, type TFunction } from './index'

interface I18nValue {
  t: TFunction
  locale: string
}

const I18nContext = createContext<I18nValue>({ t: createT('en'), locale: 'en' })

export function I18nProvider({ locale, children }: { locale: string; children: React.ReactNode }) {
  const t = createT(locale)
  return <I18nContext.Provider value={{ t, locale }}>{children}</I18nContext.Provider>
}

export function useT() {
  return useContext(I18nContext).t
}

export function useLocale(): string {
  return useContext(I18nContext).locale
}
