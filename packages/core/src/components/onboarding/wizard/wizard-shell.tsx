'use client'

import { useState } from 'react'

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
  const [currentIndex, setCurrentIndex] = useState(0)

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
      {/* Progress dots */}
      <div className="flex items-center gap-2">
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
            aria-label={step.label}
          />
        ))}
      </div>

      {/* Step content */}
      <div className="w-full">{current?.content}</div>

      {/* Navigation */}
      <div className="flex w-full items-center justify-between">
        {!isFirst ? (
          <button
            type="button"
            onClick={goBack}
            className="text-sm text-muted-foreground underline-offset-4 hover:underline"
          >
            ← Back
          </button>
        ) : (
          <span />
        )}

        <button
          type="button"
          onClick={goNext}
          className="rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground transition-colors hover:bg-primary/90"
        >
          {isLast ? 'Finish' : 'Next →'}
        </button>
      </div>
    </div>
  )
}
