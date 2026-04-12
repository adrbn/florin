'use client'

import { useRouter } from 'next/navigation'
import { useState } from 'react'
import {
  WizardShell,
  WelcomeStep,
  LocalePickerStep,
  BankingSetupStep,
  CategoryPreviewStep,
  FirstAccountStep,
  TutorialStep,
} from '@florin/core/components/onboarding/wizard/index'
import type { WizardStep } from '@florin/core/components/onboarding/wizard/index'
import type { SeedCategoryGroup } from '@florin/core/i18n/seed-categories'
import type { CreateAccountInput, ActionResult } from '@florin/core/types'

async function saveLocale(_locale: string, _currency: string): Promise<void> {
  // Locale/currency are stored in env config for desktop; persisting them as
  // user-preferences is tracked under Task 15 (Wire i18n). For now this is a
  // no-op that satisfies the wizard contract.
}

async function saveBankingConfig(appId: string, keyPath: string): Promise<void> {
  const res = await fetch('/api/settings/banking', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ appId, keyPath }),
  })
  if (!res.ok) throw new Error('Failed to save banking config')
}

async function seedCategories(groups: SeedCategoryGroup[]): Promise<void> {
  const res = await fetch('/api/onboarding/seed-categories', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ groups }),
  })
  if (!res.ok) throw new Error('Failed to seed categories')
}

async function createAccountAction(input: CreateAccountInput): Promise<ActionResult> {
  const res = await fetch('/api/accounts', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(input),
  })
  if (!res.ok) {
    const body = (await res.json().catch(() => ({}))) as { error?: string }
    return { success: false, error: body.error ?? 'Failed to create account' }
  }
  return { success: true }
}

export default function OnboardingPage() {
  const router = useRouter()
  const [locale, setLocale] = useState('en')
  const [stepIndex, setStepIndex] = useState(0)

  function advance() {
    setStepIndex((i) => i + 1)
  }

  const steps: WizardStep[] = [
    {
      id: 'welcome',
      label: 'Welcome',
      content: <WelcomeStep onGetStarted={advance} />,
    },
    {
      id: 'locale',
      label: 'Language & Currency',
      content: (
        <LocalePickerStep
          onSave={async (l, c) => {
            setLocale(l)
            await saveLocale(l, c)
            advance()
          }}
        />
      ),
    },
    {
      id: 'banking',
      label: 'Banking',
      content: (
        <BankingSetupStep
          onSave={async (appId, keyPath) => {
            await saveBankingConfig(appId, keyPath)
            advance()
          }}
          onSkip={advance}
        />
      ),
    },
    {
      id: 'categories',
      label: 'Categories',
      content: (
        <CategoryPreviewStep
          locale={locale}
          onConfirm={async (groups) => {
            await seedCategories(groups)
            advance()
          }}
        />
      ),
    },
    {
      id: 'account',
      label: 'First Account',
      content: (
        <FirstAccountStep
          onCreateAccount={async (input) => {
            const result = await createAccountAction(input)
            if (result.success) advance()
            return result
          }}
        />
      ),
    },
    {
      id: 'tutorial',
      label: 'Tutorial',
      content: (
        <TutorialStep
          onStartTutorial={() => router.push('/?tutorial=1')}
          onSkip={() => router.push('/')}
        />
      ),
    },
  ]

  // Sync wizard shell index to our manually-tracked stepIndex so steps that
  // call advance() jump forward without waiting for the shell's own Next button.
  const visibleSteps = steps.slice(stepIndex)

  return (
    <WizardShell
      key={stepIndex}
      steps={visibleSteps}
      onComplete={() => router.push('/')}
    />
  )
}
