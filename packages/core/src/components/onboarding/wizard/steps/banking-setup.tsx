'use client'

import { Landmark } from 'lucide-react'
import { useT } from '../../../../i18n/context'

interface BankingSetupStepProps {
  /**
   * Kept for API compatibility with existing callers. The wizard no longer
   * collects credentials — see the note on the component below.
   */
  onSave?: (appId: string, keyPath: string) => Promise<void>
  onSkip: () => void
}

/**
 * Onboarding's bank step — deliberately informational.
 *
 * It used to ask a brand-new user for an App ID and the "absolute path to your
 * RSA private key file (.pem)", which is both impossible for a non-technical
 * user and pointless: the desktop wizard's onSave was a no-op, so anything
 * typed here was silently discarded.
 *
 * Bank linking now lives in one place — Settings → Bank Sync — where the key is
 * generated for you in three guided steps. Onboarding just says it exists, that
 * it is optional, and where to find it.
 */
export function BankingSetupStep({ onSkip }: BankingSetupStepProps) {
  const t = useT()

  return (
    <div className="space-y-6">
      <div className="space-y-1">
        <h2 className="text-xl font-semibold">
          {t('onboarding.banking.heading', 'Connect your bank (optional)')}
        </h2>
        <p className="text-sm text-muted-foreground">
          {t(
            'onboarding.banking.body',
            'Link your bank and transactions import themselves. You can also use Florin entirely by hand, or by importing a CSV/OFX file.',
          )}
        </p>
      </div>

      <div className="flex gap-3 rounded-md border border-border bg-muted/30 p-3">
        <Landmark className="mt-0.5 h-4 w-4 shrink-0 text-primary" />
        <p className="text-xs text-muted-foreground">
          {t(
            'onboarding.banking.whereTo',
            'When you are ready, open Settings → Bank Sync. It walks you through it in three steps and takes about two minutes — once, and never again.',
          )}
        </p>
      </div>

      <button
        type="button"
        onClick={onSkip}
        className="w-full rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground transition-colors hover:bg-primary/90"
      >
        {t('onboarding.banking.continue', 'Continue')}
      </button>
    </div>
  )
}
