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
} from '@florin/core/components/onboarding/wizard'
import type { WizardStep } from '@florin/core/components/onboarding/wizard'
import type { SeedCategoryGroup } from '@florin/core/i18n/seed-categories'
import type { CreateAccountInput, ActionResult, CreateGroupInput, CreateCategoryInput } from '@florin/core/types'

interface OnboardingWizardClientProps {
  onCreateAccount: (input: CreateAccountInput) => Promise<ActionResult<{ id: string }>>
  onCreateCategoryGroup: (input: CreateGroupInput) => Promise<ActionResult<{ id: string }>>
  onCreateCategory: (input: CreateCategoryInput) => Promise<ActionResult<{ id: string }>>
}

export function OnboardingWizardClient({
  onCreateAccount,
  onCreateCategoryGroup,
  onCreateCategory,
}: OnboardingWizardClientProps) {
  const router = useRouter()
  const [locale, setLocale] = useState('en')
  // Track current step manually so individual steps can advance on their own
  // (e.g. welcome button, skip buttons) without waiting for the shell's Next.
  const [stepIndex, setStepIndex] = useState(0)

  function advance() {
    setStepIndex((i) => i + 1)
  }

  async function handleSeedCategories(groups: SeedCategoryGroup[]) {
    for (const group of groups) {
      const groupResult = await onCreateCategoryGroup({
        name: group.name,
        kind: group.kind,
        color: group.color,
      })
      if (!groupResult.success || !groupResult.data) continue

      const groupId = groupResult.data.id
      for (const cat of group.categories) {
        if (!cat.name.trim()) continue
        await onCreateCategory({
          groupId,
          name: cat.name,
          emoji: cat.emoji ?? null,
          isFixed: cat.isFixed ?? false,
        })
      }
    }
  }

  const allSteps: WizardStep[] = [
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
          onSave={async (l, _c) => {
            setLocale(l)
            // Locale/currency persistence tracked under Task 15 (Wire i18n).
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
          onSave={async (_appId, _keyPath) => {
            // Banking env config is set at the OS level for desktop; this step
            // is informational only. Full wiring is in Task 11/20.
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
            await handleSeedCategories(groups)
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
            const result = await onCreateAccount(input)
            if (result.success) advance()
            return result
          }}
        />
      ),
    },
    {
      id: 'tutorial',
      label: "You're set!",
      content: (
        <TutorialStep
          onStartTutorial={() => router.push('/?tutorial=1')}
          onSkip={() => router.push('/')}
        />
      ),
    },
  ]

  // Slice from the current step index so the shell's own progress dots reflect
  // remaining steps rather than the full list.
  const visibleSteps = allSteps.slice(stepIndex)

  return (
    <WizardShell
      key={stepIndex}
      steps={visibleSteps}
      onComplete={() => router.push('/')}
    />
  )
}
