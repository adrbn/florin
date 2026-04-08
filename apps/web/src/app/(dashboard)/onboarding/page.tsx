import { count, eq } from 'drizzle-orm'
import { OnboardingWizard } from '@/components/onboarding/onboarding-wizard'
import { db } from '@/db/client'
import { accounts, categories } from '@/db/schema'
import { isEnableBankingConfigured } from '@/server/banking/enable-banking'

/**
 * Onboarding entry point. Server-fetches the "is the install fresh" flags so
 * the wizard can skip steps the user has already completed (e.g. categories
 * are seeded by the migration script — no point asking the user to add some).
 */
export default async function OnboardingPage() {
  const [accountRow, categoryRow] = await Promise.all([
    db.select({ value: count() }).from(accounts).where(eq(accounts.isArchived, false)),
    db.select({ value: count() }).from(categories).where(eq(categories.isArchived, false)),
  ])
  const hasAccounts = Number(accountRow[0]?.value ?? 0) > 0
  const hasCategories = Number(categoryRow[0]?.value ?? 0) > 0

  return (
    <OnboardingWizard
      bankingEnabled={isEnableBankingConfigured()}
      hasAccounts={hasAccounts}
      hasCategories={hasCategories}
    />
  )
}
