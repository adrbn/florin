'use client'

import Link from 'next/link'
import { useRouter } from 'next/navigation'
import { useState } from 'react'
import { AccountForm } from '../accounts/account-form'
import { Button } from '../ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '../ui/card'
import { useT } from '../../i18n/context'
import type { ActionResult, CreateAccountInput, UpdateAccountInput } from '../../types/index'

interface OnboardingWizardProps {
  bankingEnabled: boolean
  hasAccounts: boolean
  hasCategories: boolean
  onCreateAccount: (input: CreateAccountInput) => Promise<ActionResult<{ id: string }>>
  onUpdateAccount: (input: UpdateAccountInput) => Promise<ActionResult>
}

const STEPS = ['welcome', 'account', 'categories', 'bank', 'done'] as const
type Step = (typeof STEPS)[number]

/**
 * 5-step first-run wizard. Lives client-side so the user can navigate back
 * and forth without losing form state. Each step optionally consults
 * server-rendered flags (hasAccounts, etc.) to skip steps that are already
 * done — handy when a returning user pokes /onboarding manually.
 */
export function OnboardingWizard({
  bankingEnabled,
  hasAccounts,
  hasCategories,
  onCreateAccount,
  onUpdateAccount,
}: OnboardingWizardProps) {
  const t = useT()
  const router = useRouter()
  const [step, setStep] = useState<Step>(hasAccounts ? 'categories' : 'welcome')

  const goNext = () => {
    const idx = STEPS.indexOf(step)
    const next = STEPS[Math.min(idx + 1, STEPS.length - 1)]
    if (next) setStep(next)
  }
  const goPrev = () => {
    const idx = STEPS.indexOf(step)
    const prev = STEPS[Math.max(idx - 1, 0)]
    if (prev) setStep(prev)
  }

  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <ProgressBar step={step} />

      {step === 'welcome' && (
        <Card>
          <CardHeader>
            <CardTitle className="text-2xl">{t('onboarding.welcomeTitle', 'Welcome to Florin 👋')}</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4 text-sm text-muted-foreground">
            <p>{t('onboarding.welcomeBody1', 'Florin is a self-hostable personal finance dashboard. Your data lives in your own Postgres — there is no cloud, no telemetry, and no third party between you and your numbers.')}</p>
            <p>{t('onboarding.welcomeBody2', "In this short walkthrough you'll create your first account, glance at the default categories, and (optionally) link a bank via PSD2. The whole thing takes about a minute.")}</p>
            <div className="flex justify-end">
              <Button onClick={goNext}>{t('onboarding.getStarted', 'Get started →')}</Button>
            </div>
          </CardContent>
        </Card>
      )}

      {step === 'account' && (
        <Card>
          <CardHeader>
            <CardTitle>{t('onboarding.createFirstAccount', 'Create your first account')}</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4">
            <p className="text-sm text-muted-foreground">
              {t('onboarding.firstAccountBody', "Add a checking account, a savings account, cash, or anything else you'd like to track. You can add more later — this is just to get started.")}
            </p>
            <AccountForm onSuccess={goNext} onCreateAccount={onCreateAccount} onUpdateAccount={onUpdateAccount} />
            <div className="flex justify-between">
              <Button variant="ghost" onClick={goPrev}>
                {t('onboarding.back', '← Back')}
              </Button>
              <Button variant="ghost" onClick={goNext}>
                {t('onboarding.skipForNow', 'Skip for now →')}
              </Button>
            </div>
          </CardContent>
        </Card>
      )}

      {step === 'categories' && (
        <Card>
          <CardHeader>
            <CardTitle>{t('onboarding.categoriesTitle', 'Categories')}</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4 text-sm">
            {hasCategories ? (
              <p className="text-muted-foreground">
                {t('onboarding.categoriesAlready', 'Florin already seeded a default set of expense and income categories. You can rename, reshape or extend them from the')}{' '}
                <Link href="/categories" className="text-primary underline underline-offset-2">
                  {t('onboarding.categoriesPage', 'Categories page')}
                </Link>
                .
              </p>
            ) : (
              <p className="text-muted-foreground">
                {t('onboarding.categoriesNone', "You haven't created any categories yet. Head to the")}{' '}
                <Link href="/categories" className="text-primary underline underline-offset-2">
                  {t('onboarding.categoriesPage', 'Categories page')}
                </Link>{' '}
                {t('onboarding.categoriesThenBack', 'to add some, then come back here.')}
              </p>
            )}
            <div className="flex justify-between">
              <Button variant="ghost" onClick={goPrev}>
                {t('onboarding.back', '← Back')}
              </Button>
              <Button onClick={goNext}>{t('onboarding.continue', 'Continue →')}</Button>
            </div>
          </CardContent>
        </Card>
      )}

      {step === 'bank' && (
        <Card>
          <CardHeader>
            <CardTitle>{t('onboarding.bankTitle', 'Connect a bank (optional)')}</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4 text-sm">
            {bankingEnabled ? (
              <>
                <p className="text-muted-foreground">
                  {t('onboarding.bankEnabledBody', 'Florin can pull live transactions from any EU bank that supports PSD2 via Enable Banking. New imports land in the Review queue — you confirm payee + category before they count.')}
                </p>
                <Link
                  href="/accounts/connect"
                  className="inline-flex items-center rounded-md border border-primary bg-primary px-3 py-1.5 text-xs font-medium text-primary-foreground hover:bg-primary/90"
                >
                  {t('onboarding.bankLinkBtn', 'Link a bank →')}
                </Link>
              </>
            ) : (
              <p className="text-muted-foreground">
                {t('onboarding.bankDisabledBody', 'Bank linking is not configured on this instance. To enable it, set the')}
                <code className="mx-1 font-mono text-foreground">ENABLE_BANKING_*</code>
                {t('onboarding.bankDisabledEnd', 'environment variables and restart. Florin works fine without bank linking — you can keep tracking everything manually.')}
              </p>
            )}
            <div className="flex justify-between">
              <Button variant="ghost" onClick={goPrev}>
                {t('onboarding.back', '← Back')}
              </Button>
              <Button onClick={goNext}>{t('onboarding.skipForNow', 'Skip for now →')}</Button>
            </div>
          </CardContent>
        </Card>
      )}

      {step === 'done' && (
        <Card>
          <CardHeader>
            <CardTitle>{t('onboarding.doneTitle', "You're all set 🎉")}</CardTitle>
          </CardHeader>
          <CardContent className="space-y-4 text-sm">
            <p className="text-muted-foreground">
              {t('onboarding.doneBody', "That's it — you can start adding transactions, glance at the dashboard, and use the Reflect tab once you have a few weeks of data. Enjoy.")}
            </p>
            <ul className="ml-4 list-disc space-y-1 text-muted-foreground">
              <li>
                <Link href="/" className="text-primary underline underline-offset-2">
                  {t('onboarding.linkDashboard', 'Dashboard')}
                </Link>{' '}
                {t('onboarding.linkDashboardSuffix', '— KPIs and trend lines.')}
              </li>
              <li>
                <Link href="/transactions" className="text-primary underline underline-offset-2">
                  {t('onboarding.linkTransactions', 'Transactions')}
                </Link>{' '}
                {t('onboarding.linkTransactionsSuffix', '— full ledger.')}
              </li>
              <li>
                <Link href="/reflect" className="text-primary underline underline-offset-2">
                  {t('onboarding.linkReflect', 'Reflect')}
                </Link>{' '}
                {t('onboarding.linkReflectSuffix', '— long-window analytics.')}
              </li>
              <li>
                <Link href="/tools" className="text-primary underline underline-offset-2">
                  {t('onboarding.linkTools', 'Tools')}
                </Link>{' '}
                {t('onboarding.linkToolsSuffix', '— loan + compound interest calculators.')}
              </li>
            </ul>
            <div className="flex justify-end">
              <Button onClick={() => router.push('/')}>{t('onboarding.openDashboard', 'Open dashboard')}</Button>
            </div>
          </CardContent>
        </Card>
      )}
    </div>
  )
}

function ProgressBar({ step }: { step: Step }) {
  const t = useT()
  const idx = STEPS.indexOf(step)
  const pct = ((idx + 1) / STEPS.length) * 100
  return (
    <div className="space-y-2">
      <div className="flex items-center justify-between text-[11px] uppercase tracking-wide text-muted-foreground">
        <span>
          {t('onboarding.stepOf', { current: idx + 1, total: STEPS.length }, `Step ${idx + 1} of ${STEPS.length}`)}
        </span>
        <span>{Math.round(pct)}%</span>
      </div>
      <div className="h-1.5 overflow-hidden rounded-full bg-muted">
        <div
          className="h-full bg-primary transition-[width] duration-300"
          style={{ width: `${pct}%` }}
        />
      </div>
    </div>
  )
}
