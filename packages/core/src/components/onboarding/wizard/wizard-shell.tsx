'use client'

import { useEffect, useRef, useState } from 'react'
import { useT } from '../../../i18n/context'

export interface WizardStep {
  id: string
  label: string
  content: React.ReactNode
}

interface WizardShellProps {
  steps: WizardStep[]
  onComplete: () => void
}

export function WizardShell({ steps, onComplete }: WizardShellProps) {
  const t = useT()
  const [currentIndex, setCurrentIndex] = useState(0)
  const stepRef = useRef<HTMLDivElement>(null)
  const landed = useRef(false)

  /*
   * Changer d'étape ne se voyait qu'à l'écran.
   *
   * Le contenu est remplacé sur place, sans rien qui bouge dans l'ordre de
   * lecture : un lecteur d'écran restait sur le bouton « Suivant » et ne
   * lisait rien de la nouvelle étape. Poser le focus sur le bloc d'étape le
   * fait annoncer son nom puis son titre, c'est-à-dire exactement ce qui
   * vient de changer.
   *
   * Pas au premier rendu : voler le focus à l'ouverture d'une page est aussi
   * désagréable que ne pas le déplacer du tout.
   */
  useEffect(() => {
    if (!landed.current) {
      landed.current = true
      return
    }
    stepRef.current?.focus()
  }, [currentIndex])

  const isFirst = currentIndex === 0
  const isLast = currentIndex === steps.length - 1
  const current = steps[currentIndex]

  function goBack() {
    setCurrentIndex((i) => Math.max(0, i - 1))
  }

  function goNext() {
    if (isLast) {
      onComplete()
    } else {
      setCurrentIndex((i) => Math.min(steps.length - 1, i + 1))
    }
  }

  return (
    <div className="mx-auto flex min-h-dvh max-w-xl flex-col items-center justify-center gap-8 px-4 py-12">
      {/*
        Progress dots. L'`aria-label` posé sur chaque point était perdu : sur
        un `div` sans rôle, il n'est pas restitué. La barre entière porte donc
        la progression, et les points redeviennent ce qu'ils sont, de la
        décoration.
      */}
      <div
        className="flex items-center gap-2"
        role="progressbar"
        aria-valuemin={1}
        aria-valuemax={steps.length}
        aria-valuenow={currentIndex + 1}
        aria-valuetext={t(
          'onboarding.wizard.progress',
          { n: currentIndex + 1, total: steps.length, label: current?.label ?? '' },
          'Step {n} of {total}: {label}',
        )}
      >
        {steps.map((step, i) => (
          <div
            key={step.id}
            className={[
              'h-2 rounded-full transition-all duration-300',
              i === currentIndex
                ? 'w-6 bg-primary'
                : i < currentIndex
                  ? 'w-2 bg-primary/60'
                  : 'w-2 bg-muted',
            ].join(' ')}
            aria-hidden="true"
          />
        ))}
      </div>

      {/* Step content */}
      <div
        ref={stepRef}
        tabIndex={-1}
        role="group"
        aria-label={current?.label}
        className="w-full outline-none"
      >
        {current?.content}
      </div>

      {/* Navigation */}
      <div className="flex w-full items-center justify-between">
        {!isFirst ? (
          <button
            type="button"
            onClick={goBack}
            className="text-sm text-muted-foreground underline-offset-4 hover:underline"
          >
            {t('onboarding.wizard.back', '← Back')}
          </button>
        ) : (
          <span />
        )}

        <button
          type="button"
          onClick={goNext}
          className="rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground transition-colors hover:bg-primary/90"
        >
          {isLast ? t('onboarding.wizard.finish', 'Finish') : t('onboarding.wizard.next', 'Next →')}
        </button>
      </div>
    </div>
  )
}
