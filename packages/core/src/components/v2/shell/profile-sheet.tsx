'use client'

import { useEffect, useState, useTransition } from 'react'
import {
  Calculator,
  Eye,
  EyeOff,
  Inbox,
  Languages,
  Palette,
  PiggyBank,
  Settings,
  Tags,
} from 'lucide-react'
import Link from 'next/link'
import { useTheme } from 'next-themes'
import { normalizeLocale, SUPPORTED_LOCALES, type SupportedLocale } from '../../../i18n'
import { usePrivacy } from '../../../privacy'
import { useV2T } from '../i18n/context'
import { useV2Config } from '../lib/config'
import { Row, RowGroup } from '../primitives/row'
import { Segmented } from '../primitives/segmented'
import { Sheet } from '../primitives/sheet'
import { V2_BASE } from './nav'
import { cn } from '../../../lib/utils'

/**
 * Everything that is not a daily destination: Plan, Review, Categories, Tools,
 * Settings, plus the three switches (theme, language, privacy) that used to
 * live as icon buttons in the old mobile top bar.
 *
 * Putting them behind the header avatar is what frees the tab bar to hold five
 * things instead of nine — and it is where a phone user already looks for
 * "the rest of the app".
 */
export function ProfileSheet({
  open,
  onClose,
  reviewCount,
  version,
  localeEndpoint = '/api/locale',
  signOut,
}: {
  open: boolean
  onClose: () => void
  reviewCount: number
  version: string
  localeEndpoint?: string
  signOut?: React.ReactNode
}) {
  const t = useV2T()
  const { locale } = useV2Config()
  const { hidden, toggle } = usePrivacy()
  const { theme, setTheme } = useTheme()
  const [mounted, setMounted] = useState(false)
  const [pending, startTransition] = useTransition()

  // `theme` is unknown until the client has read localStorage; rendering the
  // segmented control before then would flash the wrong active pill.
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

  const links = [
    {
      href: `${V2_BASE}/review`,
      icon: Inbox,
      label: t('v2.profile.review', 'To review'),
      hint: t('v2.profile.reviewHint', 'Categorize imported transactions'),
      badge: reviewCount,
    },
    {
      href: `${V2_BASE}/plan`,
      icon: PiggyBank,
      label: t('v2.profile.plan', 'Plan'),
      hint: t('v2.profile.planHint', "Assign this month's income"),
    },
    {
      href: `${V2_BASE}/categories`,
      icon: Tags,
      label: t('v2.profile.categories', 'Categories'),
      hint: t('v2.profile.categoriesHint', 'Spending groups and categories'),
    },
    {
      href: `${V2_BASE}/tools`,
      icon: Calculator,
      label: t('v2.profile.tools', 'Tools'),
      hint: t('v2.profile.toolsHint', 'Saving and loan simulators'),
    },
    {
      href: `${V2_BASE}/settings`,
      icon: Settings,
      label: t('v2.profile.settings', 'Settings'),
      hint: t('v2.profile.settingsHint', 'Theme, language, privacy'),
    },
  ]

  return (
    <Sheet open={open} onClose={onClose} title={t('v2.profile.title', 'More')}>
      <div className="flex flex-col gap-5 pt-1">
        <div className="v2-gutter">
          <RowGroup>
            {links.map((l) => {
              const Icon = l.icon
              return (
                <Link key={l.href} href={l.href as never} onClick={onClose} className="block">
                  <Row
                    leading={
                      <span className="v2-bubble h-9 w-9 rounded-xl">
                        <Icon className="h-4 w-4" />
                      </span>
                    }
                    title={l.label}
                    subtitle={l.hint}
                    value={
                      l.badge && l.badge > 0 ? (
                        <span className="v2-pill v2-pill-neg">{l.badge}</span>
                      ) : undefined
                    }
                    chevron
                  />
                </Link>
              )
            })}
          </RowGroup>
        </div>

        <div className="v2-gutter flex flex-col gap-3">
          <span className="v2-eyebrow">{t('v2.settings.appearance', 'Appearance')}</span>
          {/* Both switches carry a leading icon so their tracks line up; one
              indented and one flush read as a layout slip. */}
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
        </div>

        <div className="v2-gutter">
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

        <div className="v2-gutter flex flex-col items-center gap-2 pt-1">
          <Link
            href={'/' as never}
            className="v2-btn v2-btn-soft w-full"
            onClick={onClose}
          >
            {t('v2.settings.classicUi', 'Back to the classic interface')}
          </Link>
          {signOut}
          <p className="v2-micro flex items-center gap-2 pt-1">
            <span className="v2-pill v2-pill-accent">{t('v2.settings.v2Badge', 'v2 interface')}</span>
            {t('v2.settings.version', { version }, 'Version {version}')}
          </p>
        </div>
      </div>
    </Sheet>
  )
}
