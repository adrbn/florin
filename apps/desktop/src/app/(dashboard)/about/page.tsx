import { ExternalLink } from 'lucide-react'
import { BugReport } from '@/components/bug-report'

export default function AboutPage() {
  return (
    <div className="mx-auto max-w-lg space-y-8 py-8">
      <div className="text-center space-y-2">
        <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-2xl bg-primary/10">
          <span className="text-3xl" aria-hidden>
            💶
          </span>
        </div>
        <h1 className="text-2xl font-bold tracking-tight">Florin</h1>
        <p className="text-sm text-muted-foreground">
          Your finances, your machine.
        </p>
      </div>

      <div className="rounded-lg border bg-card p-6 space-y-4">
        <div className="flex justify-between text-sm">
          <span className="text-muted-foreground">Version</span>
          <span className="font-medium">0.1.0</span>
        </div>
        <div className="flex justify-between text-sm">
          <span className="text-muted-foreground">Developer</span>
          <span className="font-medium">Goldian</span>
        </div>
        <div className="flex justify-between text-sm">
          <span className="text-muted-foreground">License</span>
          <span className="font-medium">Commercial</span>
        </div>
      </div>

      <div className="rounded-lg border bg-card p-6 space-y-3">
        <h2 className="text-sm font-semibold">Links</h2>
        <a
          href="https://github.com/goldian-dev/florin"
          target="_blank"
          rel="noopener noreferrer"
          className="flex items-center gap-2 text-sm text-primary hover:underline"
        >
          <ExternalLink className="h-3.5 w-3.5" />
          GitHub Repository
        </a>
        <a
          href="https://github.com/goldian-dev/florin/issues"
          target="_blank"
          rel="noopener noreferrer"
          className="flex items-center gap-2 text-sm text-primary hover:underline"
        >
          <ExternalLink className="h-3.5 w-3.5" />
          Report an Issue
        </a>
        <a
          href="https://github.com/goldian-dev/florin/releases"
          target="_blank"
          rel="noopener noreferrer"
          className="flex items-center gap-2 text-sm text-primary hover:underline"
        >
          <ExternalLink className="h-3.5 w-3.5" />
          Release Notes
        </a>
      </div>

      <BugReport />

      <p className="text-center text-xs text-muted-foreground">
        Privacy-first personal finance dashboard.
        <br />
        All data stays on your computer.
      </p>
    </div>
  )
}
