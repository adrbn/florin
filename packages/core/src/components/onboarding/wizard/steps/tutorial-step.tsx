'use client'

interface TutorialStepProps {
  onStartTutorial: () => void
  onSkip: () => void
}

export function TutorialStep({ onStartTutorial, onSkip }: TutorialStepProps) {
  return (
    <div className="flex flex-col items-center gap-6 py-8 text-center">
      <div className="text-5xl">🎉</div>
      <div className="space-y-2">
        <h2 className="text-2xl font-bold tracking-tight">You're all set!</h2>
        <p className="text-sm text-muted-foreground">
          Your accounts and categories are ready. Would you like a quick walkthrough of the main
          features?
        </p>
      </div>

      <div className="flex w-full flex-col gap-3">
        <button
          type="button"
          onClick={onStartTutorial}
          className="rounded-md bg-primary px-6 py-2.5 text-sm font-medium text-primary-foreground transition-colors hover:bg-primary/90"
        >
          Start interactive tutorial
        </button>
        <button
          type="button"
          onClick={onSkip}
          className="text-sm text-muted-foreground underline-offset-4 hover:underline"
        >
          Skip to dashboard
        </button>
      </div>
    </div>
  )
}
