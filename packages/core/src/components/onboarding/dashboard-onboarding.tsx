'use client'

import { useState } from 'react'
import { DashboardTour } from './dashboard-tour'
import { GettingStartedCard, type GettingStartedState } from './getting-started-card'

/**
 * What a brand-new user sees on the dashboard right after their first account
 * exists: a "first steps" checklist plus a one-time spotlight tour. Bundled
 * into a single client component so each app only has to render one thing and
 * the card's "replay the tour" link can drive the tour.
 */
export function DashboardOnboarding(props: GettingStartedState) {
  const [replayToken, setReplayToken] = useState(0)

  return (
    <>
      <GettingStartedCard {...props} onReplayTour={() => setReplayToken((n) => n + 1)} />
      <DashboardTour enabled={props.hasAccount} replayToken={replayToken} />
    </>
  )
}
