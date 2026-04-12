'use client'

import { useState } from 'react'
import { Bug, Send, CheckCircle } from 'lucide-react'

export function BugReport() {
  const [message, setMessage] = useState('')
  const [sent, setSent] = useState(false)

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!message.trim()) return

    const logs = collectLogs()
    const body = `${message}\n\n--- System Info ---\n${logs}`
    const mailto = `mailto:bug@labr.studio?subject=${encodeURIComponent(
      `[Florin Bug] ${message.slice(0, 60)}`
    )}&body=${encodeURIComponent(body)}`

    window.open(mailto, '_blank')
    setSent(true)
    setTimeout(() => {
      setSent(false)
      setMessage('')
    }, 3000)
  }

  return (
    <div className="rounded-lg border bg-card p-6 space-y-4">
      <div className="flex items-center gap-2">
        <Bug className="h-4 w-4 text-muted-foreground" />
        <h2 className="text-sm font-semibold">Report a Bug</h2>
      </div>

      {sent ? (
        <div className="flex items-center gap-2 text-sm text-emerald-600 dark:text-emerald-400">
          <CheckCircle className="h-4 w-4" />
          Email client opened — thanks for the report!
        </div>
      ) : (
        <form onSubmit={handleSubmit} className="space-y-3">
          <textarea
            value={message}
            onChange={(e) => setMessage(e.target.value)}
            placeholder="Describe what happened and what you expected…"
            rows={3}
            className="w-full rounded-md border border-input bg-background px-3 py-2 text-sm shadow-sm placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-ring resize-none"
          />
          <button
            type="submit"
            disabled={!message.trim()}
            className="inline-flex items-center gap-2 rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground shadow-sm transition-colors hover:bg-primary/90 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            <Send className="h-3.5 w-3.5" />
            Send Bug Report
          </button>
          <p className="text-[11px] text-muted-foreground">
            Opens your email client with system info attached. No data leaves your machine without your confirmation.
          </p>
        </form>
      )}
    </div>
  )
}

function collectLogs(): string {
  const lines = [
    `App: Florin v0.1.0`,
    `Platform: ${navigator.platform}`,
    `User Agent: ${navigator.userAgent}`,
    `Screen: ${screen.width}x${screen.height} @ ${devicePixelRatio}x`,
    `Window: ${window.innerWidth}x${window.innerHeight}`,
    `Locale: ${navigator.language}`,
    `Time: ${new Date().toISOString()}`,
    `Online: ${navigator.onLine}`,
  ]
  return lines.join('\n')
}
