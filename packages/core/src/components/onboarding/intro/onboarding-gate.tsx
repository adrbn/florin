'use client'

import { useEffect, useState } from 'react'
import { OnboardingIntro } from './onboarding-intro'

/** Bump to replay the intro for everyone after a meaningful rewrite. */
const INTRO_SEEN_KEY = 'florin:intro:v1'

interface OnboardingGateProps {
  /** The functional setup wizard, shown once the intro is done or skipped. */
  children: React.ReactNode
}

/**
 * Shows the slide introduction the first time someone lands on /onboarding,
 * then hands over to the real setup wizard.
 *
 * Renders `children` on the server pass and until mount, so the wizard is what
 * exists without JavaScript and what a returning user sees immediately — the
 * intro is strictly additive and can never block setup.
 */
export function OnboardingGate({ children }: OnboardingGateProps) {
  const [showIntro, setShowIntro] = useState(false)

  useEffect(() => {
    try {
      if (window.localStorage.getItem(INTRO_SEEN_KEY) !== '1') setShowIntro(true)
    } catch {
      // Storage unavailable (private mode) — skip straight to the wizard rather
      // than replaying the intro on every visit.
    }
  }, [])

  function dismiss() {
    try {
      window.localStorage.setItem(INTRO_SEEN_KEY, '1')
    } catch {
      // Non-fatal.
    }
    setShowIntro(false)
  }

  if (showIntro) {
    return <OnboardingIntro onFinish={dismiss} onSkip={dismiss} />
  }
  return <>{children}</>
}
