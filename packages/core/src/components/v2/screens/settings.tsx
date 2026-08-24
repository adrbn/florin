'use client'

import { useEffect, useState, useTransition } from 'react'
import { Check, Eye, EyeOff, Landmark, Languages, Palette } from 'lucide-react'
import Link from 'next/link'
import { useTheme } from 'next-themes'
import { normalizeLocale, SUPPORTED_LOCALES, type SupportedLocale } from '../../../i18n'
import { usePrivacy } from '../../../privacy'
import { useV2T } from '../i18n/context'
import { useV2Config } from '../lib/config'
import { Card, Pill, Section } from '../primitives/atoms'
import { Row, RowGroup } from '../primitives/row'
import { Segmented } from '../primitives/segmented'
import { Screen } from '../shell/screen'
import { V2_BASE } from '../shell/nav'
import { cn } from '../../../lib/utils'

export function SettingsScreen({
  version,
  bankSyncConfigured,
  localeEndpoint = '/api/locale',
  signOut,
}: {
  version: string
  bankSyncConfigured: boolean
  localeEndpoint?: string
  signOut?: React.ReactNode
}) {
  const t = useV2T()
  const { locale } = useV2Config()
  const { hidden, toggle } = usePrivacy()
  const { theme, setTheme } = useTheme()
  const [mounted, setMounted] = useState(false)
  const [pending, startTransition] = useTransition()

  useEffect(() => setMounted(true), [])

  const current: SupportedLocale = normalizeLocale(locale)

  const setLocale = (next: SupportedLocale) => {
    if (next === current) return
    startTransition(async () => {
      await fetch(localeEndpoint, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ locale: next }),
      })
      window.location.reload()
    })
  }

  const hero = (
    <div className="v2-gutter flex flex-col gap-1 pb-1">
      <h2 className="text-[30px] font-semibold leading-tight tracking-[-0.035em]">
        {t('v2.settings.title', 'Settings')}
      </h2>
      <p className="v2-sub">{t('v2.settings.v2Hint', 'Mobile redesign — in testing.')}</p>
    </div>
  )

  return (
    <Screen title={t('v2.settings.title', 'Settings')} hero={hero} back="/m" hideProfile>
      <Section title={t('v2.settings.appearance', 'Appearance')}>
        <div className="v2-gutter flex flex-col gap-3">
          <div className="flex items-center gap-2">
            <Palette aria-hidden className="h-4 w-4 flex-none text-[var(--v2-text-3)]" />
            {mounted ? (
              <Segmented
                className="flex-1"
                value={(theme as 'light' | 'dark' | 'system') ?? 'system'}
                onChange={(v) => setTheme(v)}
                options={[
                  { value: 'light', label: t('v2.settings.theme.light', 'Light') },
                  { value: 'dark', label: t('v2.settings.theme.dark', 'Dark') },
                  { value: 'system', label: t('v2.settings.theme.system', 'System') },
                ]}
              />
            ) : (
              <div className="v2-skel h-[38px] flex-1 rounded-full" />
            )}
          </div>

          <div className="flex items-center gap-2">
            <Languages aria-hidden className="h-4 w-4 flex-none text-[var(--v2-text-3)]" />
            <Segmented
              className={cn('flex-1', pending && 'opacity-60')}
              value={current}
              onChange={(v) => setLocale(v as SupportedLocale)}
              options={SUPPORTED_LOCALES.map((l) => ({ value: l.code, label: l.name }))}
            />
          </div>

          <RowGroup>
            <Row
              leading={
                <span className="v2-bubble h-9 w-9 rounded-xl">
                  {hidden ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                </span>
              }
              title={t('v2.settings.privacy', 'Hide amounts')}
              subtitle={t('v2.settings.privacyHint', 'Blurs every amount on screen')}
              value={
                <span
                  aria-hidden
                  className={cn(
                    'flex h-[26px] w-[44px] items-center rounded-full p-[3px] transition-colors',
                    hidden ? 'bg-[var(--v2-accent)]' : 'bg-[var(--v2-surface-3)]',
                  )}
                >
                  <span
                    className="h-5 w-5 rounded-full bg-white shadow transition-transform"
                    style={{ transform: hidden ? 'translateX(18px)' : 'translateX(0)' }}
                  />
                </span>
              }
              onClick={toggle}
            />
          </RowGroup>
        </div>
      </Section>

      <Section title={t('v2.settings.data', 'Data')}>
        <div className="v2-gutter">
          <RowGroup>
            <Link href={`${V2_BASE}/accounts/connect` as never} className="block">
              <Row
                leading={
                  <span className="v2-bubble h-9 w-9 rounded-xl">
                    <Landmark className="h-4 w-4" />
                  </span>
                }
                title={t('v2.settings.banking', 'Bank sync')}
                subtitle={
                  bankSyncConfigured
                    ? t('v2.settings.bankingReady', 'Configured')
                    : t('v2.settings.bankingMissing', 'Not configured')
                }
                value={
                  bankSyncConfigured ? (
                    <Check className="h-4 w-4 text-[var(--v2-pos)]" />
                  ) : undefined
                }
                chevron
              />
            </Link>
          </RowGroup>
        </div>
      </Section>

      <Section title={t('v2.settings.about', 'About')}>
        <div className="v2-gutter flex flex-col items-center gap-3">
          <Card className="flex w-full flex-col items-center gap-2 p-5">
            <span
              className="text-[26px] leading-none"
              style={{ fontFamily: "'Tuaf', ui-sans-serif, system-ui, sans-serif", letterSpacing: '-0.02em' }}
            >
              Florin
            </span>
            <Pill tone="accent">{t('v2.settings.v2Badge', 'v2 interface')}</Pill>
            <span className="v2-micro">
              {t('v2.settings.version', { version }, 'Version {version}')}
            </span>
          </Card>
          <Link href={'/' as never} className="v2-btn v2-btn-soft w-full">
            {t('v2.settings.classicUi', 'Back to the classic interface')}
          </Link>
          {signOut}
        </div>
      </Section>
    </Screen>
  )
}
