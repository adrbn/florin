'use client'

import { useCallback, useEffect, useRef, useState } from 'react'
import { ArrowRight, Landmark, LineChart, ShieldCheck, Sparkles } from 'lucide-react'
import type { LucideIcon } from 'lucide-react'
import { useT } from '../../../i18n/context'
import { BankVisual, BudgetVisual, GrowthVisual, PrivacyVisual } from './visuals'

interface OnboardingIntroProps {
  /** Continue into the functional setup wizard. */
  onFinish: () => void
  /** Same destination, but chosen early — always available. */
  onSkip?: () => void
}

interface Slide {
  key: string
  icon: LucideIcon
  eyebrow: string
  title: string
  body: string
  visual: (active: boolean) => React.ReactNode
}

const SWIPE_THRESHOLD = 48

/**
 * The first thing a new user sees: a short, skippable introduction that explains
 * what Florin is before asking them to set anything up.
 *
 * Editorial rather than dashboard-like — one idea per slide, a large brand
 * headline, generous space, and a single accent. The artwork is illustrative
 * (there is no user data yet) and animates once per slide.
 *
 * Navigable by button, arrow keys, or swipe; Escape skips. Never traps anyone:
 * "Skip" is present on every slide.
 */
export function OnboardingIntro({ onFinish, onSkip }: OnboardingIntroProps) {
  const t = useT()
  const [index, setIndex] = useState(0)
  // Drives the enter animation: flipped off during the swap so each slide's
  // artwork and text replay their reveal.
  const [entered, setEntered] = useState(false)
  const touchStartX = useRef<number | null>(null)

  const slides: Slide[] = [
    {
      key: 'welcome',
      icon: Sparkles,
      eyebrow: t('intro.eyebrowWelcome', 'Welcome'),
      title: t('intro.welcomeTitle', 'Your money,\nfinally legible.'),
      body: t(
        'intro.welcomeBody',
        'Florin gathers your accounts in one place and turns them into something you can actually read. Two minutes to set up.',
      ),
      visual: (active) => <GrowthVisual active={active} />,
    },
    {
      key: 'privacy',
      icon: ShieldCheck,
      eyebrow: t('intro.eyebrowPrivacy', 'Privacy'),
      title: t('intro.privacyTitle', 'Your data\nstays here.'),
      body: t(
        'intro.privacyBody',
        'No cloud, no tracking, no analytics. Florin keeps everything on this machine — you are the only one who ever sees your numbers.',
      ),
      visual: (active) => <PrivacyVisual active={active} />,
    },
    {
      key: 'overview',
      icon: LineChart,
      eyebrow: t('intro.eyebrowOverview', 'Overview'),
      title: t('intro.overviewTitle', 'Everything\non one screen.'),
      body: t(
        'intro.overviewBody',
        'Net worth, what you spent this month, what is left, and how long your savings would last — without opening a spreadsheet.',
      ),
      visual: (active) => <GrowthVisual active={active} />,
    },
    {
      key: 'budget',
      icon: Sparkles,
      eyebrow: t('intro.eyebrowBudget', 'Categories'),
      title: t('intro.budgetTitle', 'Every euro\nhas a job.'),
      body: t(
        'intro.budgetBody',
        'Transactions sort themselves into categories. You confirm the guesses once, and the plan keeps itself up to date.',
      ),
      visual: (active) => <BudgetVisual active={active} />,
    },
    {
      key: 'bank',
      icon: Landmark,
      eyebrow: t('intro.eyebrowBank', 'Optional'),
      title: t('intro.bankTitle', 'Connect your bank.\nOnce.'),
      body: t(
        'intro.bankBody',
        'Three steps in Settings and your transactions arrive on their own. Prefer not to? Florin works perfectly by hand or from a CSV file.',
      ),
      visual: (active) => <BankVisual active={active} />,
    },
  ]

  const total = slides.length
  const isLast = index === total - 1
  const current = slides[index]!

  // Replay the reveal whenever the slide changes.
  useEffect(() => {
    setEntered(false)
    const id = window.requestAnimationFrame(() => setEntered(true))
    return () => window.cancelAnimationFrame(id)
  }, [])

  const go = useCallback(
    (next: number) => {
      if (next < 0 || next >= total) return
      setEntered(false)
      // Let the exit settle before swapping content, so text never pops.
      window.setTimeout(() => {
        setIndex(next)
        window.requestAnimationFrame(() => setEntered(true))
      }, 140)
    },
    [total],
  )

  const advance = useCallback(() => {
    if (isLast) {
      onFinish()
      return
    }
    go(index + 1)
  }, [isLast, go, index, onFinish])

  const skip = useCallback(() => (onSkip ?? onFinish)(), [onSkip, onFinish])

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'ArrowRight' || e.key === 'Enter') advance()
      if (e.key === 'ArrowLeft') go(index - 1)
      if (e.key === 'Escape') skip()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [advance, go, index, skip])

  const Icon = current.icon

  return (
    <section
      aria-roledescription="carousel"
      aria-label={t('intro.ariaLabel', 'Introduction to Florin')}
      className="flex min-h-[100dvh] flex-col bg-background px-6 py-6 sm:px-10 sm:py-8 lg:px-16"
      onTouchStart={(e) => {
        touchStartX.current = e.touches[0]?.clientX ?? null
      }}
      onTouchEnd={(e) => {
        const start = touchStartX.current
        const end = e.changedTouches[0]?.clientX
        touchStartX.current = null
        if (start == null || end == null) return
        const dx = end - start
        if (dx <= -SWIPE_THRESHOLD) advance()
        if (dx >= SWIPE_THRESHOLD) go(index - 1)
      }}
    >
      {/* ── top rail: position + escape hatch ───────────────────────────── */}
      <header className="flex shrink-0 items-baseline justify-between">
        <p className="font-mono text-[11px] tracking-[0.18em] text-muted-foreground tabular-nums">
          {String(index + 1).padStart(2, '0')}
          <span className="mx-1.5 opacity-40">—</span>
          {String(total).padStart(2, '0')}
        </p>
        <button
          type="button"
          onClick={skip}
          className="-mr-2 rounded-md px-2 py-1 text-xs text-muted-foreground underline-offset-4 transition-colors hover:text-foreground hover:underline"
        >
          {t('intro.skip', 'Skip')}
        </button>
      </header>

      {/* ── the slide ───────────────────────────────────────────────────── */}
      <div className="flex min-h-0 flex-1 items-center py-8">
        <div className="grid w-full items-center gap-10 lg:grid-cols-[minmax(0,1fr)_minmax(0,0.85fr)] lg:gap-16">
          {/* copy */}
          <div className="min-w-0">
            <span
              className="inline-flex items-center gap-2 text-[11px] font-medium uppercase tracking-[0.16em] text-primary motion-reduce:!translate-y-0 motion-reduce:!opacity-100"
              style={{
                opacity: entered ? 1 : 0,
                transform: entered ? 'translateY(0)' : 'translateY(10px)',
                transition:
                  'opacity 500ms ease-out 60ms, transform 600ms cubic-bezier(0.22, 1, 0.36, 1) 60ms',
              }}
            >
              <Icon className="h-3.5 w-3.5" />
              {current.eyebrow}
            </span>

            <h1
              className="font-brand mt-4 whitespace-pre-line font-semibold leading-[1.03] tracking-tight text-foreground motion-reduce:!translate-y-0 motion-reduce:!opacity-100"
              style={{
                fontSize: 'clamp(2.25rem, 5.6vw, 4.25rem)',
                opacity: entered ? 1 : 0,
                transform: entered ? 'translateY(0)' : 'translateY(14px)',
                transition:
                  'opacity 600ms ease-out 130ms, transform 700ms cubic-bezier(0.22, 1, 0.36, 1) 130ms',
              }}
            >
              {current.title}
            </h1>

            <p
              className="mt-5 max-w-[46ch] text-[15px] leading-relaxed text-muted-foreground motion-reduce:!translate-y-0 motion-reduce:!opacity-100"
              style={{
                opacity: entered ? 1 : 0,
                transform: entered ? 'translateY(0)' : 'translateY(14px)',
                transition:
                  'opacity 600ms ease-out 220ms, transform 700ms cubic-bezier(0.22, 1, 0.36, 1) 220ms',
              }}
            >
              {current.body}
            </p>
          </div>

          {/* artwork — first on mobile would push the copy below the fold, so it
              trails the text there and sits alongside it from lg up */}
          <div
            aria-hidden="true"
            className="order-last h-[150px] text-foreground sm:h-[190px] lg:h-[260px]"
            style={{
              opacity: entered ? 1 : 0,
              transition: 'opacity 700ms ease-out 260ms',
            }}
          >
            {current.visual(entered)}
          </div>
        </div>
      </div>

      {/* ── bottom rail: progress + primary action ──────────────────────── */}
      <footer className="flex shrink-0 items-center justify-between gap-4">
        <div className="flex items-center gap-2" role="tablist" aria-label={t('intro.ariaSteps', 'Steps')}>
          {slides.map((s, i) => {
            const done = i === index
            return (
              <button
                key={s.key}
                type="button"
                role="tab"
                aria-selected={done}
                aria-label={`${i + 1}. ${s.eyebrow}`}
                onClick={() => go(i)}
                className="group py-2"
              >
                <span
                  className={`block h-1.5 rounded-full transition-all duration-500 ${
                    done
                      ? 'w-7 bg-primary'
                      : 'w-1.5 bg-foreground/20 group-hover:bg-foreground/40'
                  }`}
                />
              </button>
            )
          })}
        </div>

        <div className="flex items-center gap-2">
          {index > 0 && (
            <button
              type="button"
              onClick={() => go(index - 1)}
              className="rounded-md px-3 py-2 text-sm text-muted-foreground transition-colors hover:text-foreground"
            >
              {t('intro.back', 'Back')}
            </button>
          )}
          <button
            type="button"
            onClick={advance}
            className="inline-flex items-center gap-2 rounded-full bg-primary px-5 py-2.5 text-sm font-medium text-primary-foreground shadow-sm transition-transform duration-200 hover:scale-[1.02] active:scale-[0.99] motion-reduce:!transform-none"
          >
            {isLast ? t('intro.start', 'Set up Florin') : t('intro.next', 'Continue')}
            <ArrowRight className="h-4 w-4" />
          </button>
        </div>
      </footer>
    </section>
  )
}
