'use client'

import { createContext, useContext, useMemo } from 'react'
import { toLocaleTag } from '../../../i18n'
import { money, moneyCompact, percent, splitAmount, type AmountParts } from './format'

interface V2Config {
  /** App locale code: 'fr' | 'en' | 'nl'. */
  locale: string
  /** BCP-47 tag derived from it, for every Intl call. */
  tag: string
  /** ISO 4217 code the deployment runs on. */
  currency: string
}

const V2ConfigContext = createContext<V2Config>({ locale: 'fr', tag: 'fr-FR', currency: 'EUR' })

export function V2ConfigProvider({
  locale,
  currency,
  children,
}: {
  locale: string
  currency: string
  children: React.ReactNode
}) {
  const value = useMemo(
    () => ({ locale, tag: toLocaleTag(locale), currency }),
    [locale, currency],
  )
  return <V2ConfigContext.Provider value={value}>{children}</V2ConfigContext.Provider>
}

export function useV2Config(): V2Config {
  return useContext(V2ConfigContext)
}

export interface MoneyHelpers {
  tag: string
  currency: string
  /** "128 404,17 €" */
  fmt: (v: number, o?: { signed?: boolean; decimals?: boolean }) => string
  /** "128 k €" */
  compact: (v: number) => string
  /** "+12,3 %" */
  pct: (v: number | null, digits?: number) => string
  /** Parts, for the demoted-cents hero treatment. */
  parts: (v: number, o?: { signed?: boolean; decimals?: boolean }) => AmountParts
}

export function useMoney(): MoneyHelpers {
  const { tag, currency } = useV2Config()
  return useMemo(
    () => ({
      tag,
      currency,
      fmt: (v, o) => money(v, { locale: tag, currency, ...o }),
      compact: (v) => moneyCompact(v, { locale: tag, currency }),
      pct: (v, digits) => percent(v, tag, digits),
      parts: (v, o) => splitAmount(v, { locale: tag, currency, ...o }),
    }),
    [tag, currency],
  )
}
