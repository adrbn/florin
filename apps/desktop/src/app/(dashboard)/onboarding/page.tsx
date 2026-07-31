import { OnboardingWizardClient } from './onboarding-wizard-client'
import { OnboardingGate } from '@florin/core/components/onboarding/intro/onboarding-gate'
import { createAccount } from '@/server/actions/accounts'
import { createCategory, createCategoryGroup } from '@/server/actions/categories'

/**
 * First-launch onboarding page. This is a thin server component that wires
 * server actions and passes them into the client-side wizard.
 */
export default function OnboardingPage() {
  return (
    <OnboardingGate>
      <OnboardingWizardClient
        onCreateAccount={createAccount}
        onCreateCategoryGroup={createCategoryGroup}
        onCreateCategory={createCategory}
      />
    </OnboardingGate>
  )
}
