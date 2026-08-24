'use client'

import { Landmark, Sparkles, Tags, Wallet } from 'lucide-react'
import Link from 'next/link'
import { useV2T } from '../i18n/context'
import { Card } from '../primitives/atoms'
import { Screen } from '../shell/screen'
import { V2_BASE } from '../shell/nav'

/**
 * v2 welcome.
 *
 * Account creation, bank pairing and the categorisation rules editor are a
 * multi-step wizard with its own validation; re-skinning it is a separate
 * piece of work from this redesign. This screen frames the three steps in the
 * v2 language and hands over to the shipping wizard, which is honest about
 * what has been redesigned and what has not.
 */
export function OnboardingScreen({ classicHref = '/onboarding' }: { classicHref?: string }) {
  const t = useV2T()

  const steps = [
    {
      icon: Wallet,
      title: t('v2.onboarding.step1', 'Create an account'),
      hint: t('v2.onboarding.step1Hint', 'A current account to start with'),
    },
    {
      icon: Landmark,
      title: t('v2.onboarding.step2', 'Connect your bank'),
      hint: t('v2.onboarding.step2Hint', 'Optional — you can enter everything by hand'),
    },
    {
      icon: Tags,
      title: t('v2.onboarding.step3', 'Check the categories'),
      hint: t('v2.onboarding.step3Hint', 'Florin categorizes, you correct'),
    },
  ]

  const hero = (
    <div className="v2-gutter flex flex-col items-center gap-3 py-8 text-center">
      <span className="grid h-14 w-14 place-items-center rounded-[20px] bg-[var(--v2-accent-soft)] text-[var(--v2-accent-text)]">
        <Sparkles className="h-6 w-6" />
      </span>
      <h2 className="text-[32px] font-semibold leading-tight tracking-[-0.035em]">
        {t('v2.onboarding.title', 'Welcome')}
      </h2>
      <p className="v2-sub max-w-[32ch] text-balance">
        {t(
          'v2.onboarding.lead',
          "Florin keeps your finances on your own machine. Three steps and you're set.",
        )}
      </p>
    </div>
  )

  return (
    <Screen title={t('v2.onboarding.title', 'Welcome')} hero={hero} hideProfile>
      <div className="v2-gutter flex flex-col gap-3">
        {steps.map((s, i) => {
          const Icon = s.icon
          return (
            <Card key={s.title} className="flex items-center gap-3 p-4">
              <span className="v2-num w-5 flex-none text-[13px] text-[var(--v2-text-3)]">
                {i + 1}
              </span>
              <span className="v2-bubble h-9 w-9 rounded-xl">
                <Icon className="h-4 w-4" />
              </span>
              <span className="flex min-w-0 flex-1 flex-col">
                <span className="v2-title">{s.title}</span>
                <span className="v2-sub truncate">{s.hint}</span>
              </span>
            </Card>
          )
        })}
      </div>

      <div className="v2-gutter flex flex-col gap-2.5">
        <Link href={classicHref as never} className="v2-btn v2-btn-primary w-full">
          {t('v2.onboarding.start', 'Get started')}
        </Link>
        <Link href={`${V2_BASE}` as never} className="v2-btn v2-btn-ghost w-full">
          {t('v2.nav.overview', 'Overview')}
        </Link>
      </div>
    </Screen>
  )
}
