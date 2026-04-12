'use client'

interface WelcomeStepProps {
  onGetStarted: () => void
}

export function WelcomeStep({ onGetStarted }: WelcomeStepProps) {
  return (
    <div className="flex flex-col items-center gap-6 py-8 text-center">
      <div className="text-5xl">🪙</div>
      <div className="space-y-2">
        <h1 className="text-3xl font-bold tracking-tight">Welcome to Florin</h1>
        <p className="text-base text-muted-foreground">
          Your finances, your machine. All data stays on this computer.
        </p>
      </div>
      <p className="max-w-sm text-sm text-muted-foreground">
        This short setup takes about a minute. You'll pick your language and currency, preview
        default categories, and create your first account.
      </p>
      <button
        type="button"
        onClick={onGetStarted}
        className="mt-2 rounded-md bg-primary px-6 py-2.5 text-sm font-medium text-primary-foreground transition-colors hover:bg-primary/90"
      >
        Get Started
      </button>
    </div>
  )
}
