'use client'

import { type ComponentProps, useEffect, useState } from 'react'
import Link from 'next/link'
import { Check, ChevronRight, Sparkles, X } from 'lucide-react'
import { useT } from '../../i18n/context'
import { cn } from '../../lib/utils'

/**
 * Facts the card needs, all derived from queries that already exist
 * (listAccounts / countTransactions / countNeedsReview) — no new DB code.
 */
export interface GettingStartedState {
  hasAccount: boolean
  /** At least one account is linked to a bank via PSD2. */
  hasBankSync: boolean
  /** Any transaction at all (bank-synced, imported, or hand-entered). */
  hasTransactions: boolean
  /** Rows still sitting in the review queue. */
  needsReviewCount: number
}

interface GettingStartedCardProps extends GettingStartedState {
  /** Opens the guided tour again from the card's footer. */
  onReplayTour?: () => void
}

const DISMISS_KEY = 'florin:gettingStarted:dismissed'

/** Derived from next/link so typedRoutes stays satisfied in both apps. */
type StepHref = ComponentProps<typeof Link>['href']

interface StepView {
  key: string
  label: string
  hint: string
  href: StepHref
  done: boolean
}

/**
 * "Premiers pas" — the walkthrough a brand-new user gets right after creating
 * their first account, when the welcome banner (accountCount === 0) has just
 * disappeared and the dashboard would otherwise offer no guidance at all.
 *
 * Steps tick themselves off from real data rather than a stored wizard cursor,
 * so it stays honest if the user does things out of order or on the other
 * platform (web ↔ desktop share the same database contents). Once every step is
 * done the card removes itself for good; it can also be dismissed early.
 */
export function GettingStartedCard({
  hasAccount,
  hasBankSync,
  hasTransactions,
  needsReviewCount,
  onReplayTour,
}: GettingStartedCardProps) {
  const t = useT()
  // Start hidden: the dismissal flag lives in localStorage, which isn't
  // available during SSR. Rendering nothing until mount avoids a flash of a
  // card the user already dismissed (and a hydration mismatch).
  const [mounted, setMounted] = useState(false)
  const [dismissed, setDismissed] = useState(false)

  useEffect(() => {
    setMounted(true)
    try {
      setDismissed(window.localStorage.getItem(DISMISS_KEY) === '1')
    } catch {
      // Private mode / storage disabled — just show the card.
    }
  }, [])

  const steps: StepView[] = [
    {
      key: 'account',
      label: t('gettingStarted.stepAccount', 'Create an account'),
      hint: t('gettingStarted.stepAccountHint', 'Checking, savings, cash — anything you want to track.'),
      href: '/accounts',
      done: hasAccount,
    },
    {
      key: 'bank',
      label: t('gettingStarted.stepBank', 'Connect your bank'),
      hint: t('gettingStarted.stepBankHint', 'Optional — transactions import themselves afterwards.'),
      href: '/accounts/connect',
      done: hasBankSync,
    },
    {
      key: 'transactions',
      label: t('gettingStarted.stepTransactions', 'Get some transactions in'),
      hint: t('gettingStarted.stepTransactionsHint', 'Sync your bank, drop in a CSV/OFX file, or add one by hand.'),
      href: '/transactions',
      done: hasTransactions,
    },
    {
      key: 'review',
      label: t('gettingStarted.stepReview', 'Categorize your spending'),
      hint: t('gettingStarted.stepReviewHint', 'Florin guesses categories — confirm them in the review queue.'),
      href: '/review',
      done: hasTransactions && needsReviewCount === 0,
    },
  ]

  const doneCount = steps.filter((s) => s.done).length
  const allDone = doneCount === steps.length

  // Never shown before the first account exists (the welcome banner covers
  // that), once everything is done, or after an explicit dismissal.
  if (!mounted || !hasAccount || allDone || dismissed) return null

  function handleDismiss() {
    setDismissed(true)
    try {
      window.localStorage.setItem(DISMISS_KEY, '1')
    } catch {
      // Non-fatal — it just reappears next time.
    }
  }

  return (
    <div
      data-tour="checklist"
      className="rounded-lg border border-primary/30 bg-primary/5 px-4 py-3 shadow-sm"
    >
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="flex items-center gap-1.5 text-sm font-semibold text-foreground">
            <Sparkles className="h-3.5 w-3.5 shrink-0 text-primary" />
            {t('gettingStarted.title', 'First steps')}
          </p>
          <p className="mt-0.5 text-xs text-muted-foreground">
            {t(
              'gettingStarted.subtitle',
              { done: doneCount, total: steps.length },
              `${doneCount} of ${steps.length} done`,
            )}
          </p>
        </div>
        <button
          type="button"
          onClick={handleDismiss}
          aria-label={t('gettingStarted.dismiss', 'Hide')}
          title={t('gettingStarted.dismiss', 'Hide')}
          className="-mr-1 shrink-0 rounded-md p-1 text-muted-foreground transition-colors hover:bg-foreground/10 hover:text-foreground"
        >
          <X className="h-4 w-4" />
        </button>
      </div>

      {/* Progress */}
      <div className="mt-2 h-1 overflow-hidden rounded-full bg-foreground/10">
        <div
          className="h-full rounded-full bg-primary transition-[width] duration-500"
          style={{ width: `${(doneCount / steps.length) * 100}%` }}
        />
      </div>

      <ul className="mt-3 space-y-1">
        {steps.map((step) => (
          <li key={step.key}>
            {step.done ? (
              <div className="flex items-center gap-2 px-1 py-1.5 text-xs text-muted-foreground">
                <span className="flex h-4 w-4 shrink-0 items-center justify-center rounded-full bg-emerald-500/15">
                  <Check className="h-3 w-3 text-emerald-600 dark:text-emerald-400" />
                </span>
                <span className="line-through">{step.label}</span>
              </div>
            ) : (
              <Link
                href={step.href}
                className="group flex items-center gap-2 rounded-md px-1 py-1.5 transition-colors hover:bg-foreground/5"
              >
                <span className="h-4 w-4 shrink-0 rounded-full border border-muted-foreground/40" />
                <span className="min-w-0 flex-1">
                  <span className="block text-xs font-medium text-foreground">{step.label}</span>
                  <span className="block text-[11px] text-muted-foreground">{step.hint}</span>
                </span>
                <ChevronRight className="h-3.5 w-3.5 shrink-0 text-muted-foreground transition-transform group-hover:translate-x-0.5" />
              </Link>
            )}
          </li>
        ))}
      </ul>

      {onReplayTour && (
        <button
          type="button"
          onClick={onReplayTour}
          className={cn(
            'mt-1 rounded-md px-1 py-1 text-[11px] text-muted-foreground underline-offset-2',
            'transition-colors hover:text-foreground hover:underline',
          )}
        >
          {t('gettingStarted.replayTour', 'Replay the tour')}
        </button>
      )}
    </div>
  )
}
