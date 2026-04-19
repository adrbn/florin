'use client'

import { Check, RefreshCw } from 'lucide-react'
import { useEffect, useRef, useState, useTransition } from 'react'
import { Button } from '../ui/button'
import { cn } from '../../lib/utils'

interface SyncResult {
  success: boolean
  error?: string
  data?: { connectionsSynced: number; transactionsInserted: number } | null
}

interface SyncAllButtonProps {
  onSyncAllBanks: () => Promise<SyncResult>
}

const SUCCESS_HOLD_MS = 5000

export function SyncAllButton({ onSyncAllBanks }: SyncAllButtonProps) {
  const [pending, startTransition] = useTransition()
  const [feedback, setFeedback] = useState<string | null>(null)
  const [isError, setIsError] = useState(false)
  const [justSucceeded, setJustSucceeded] = useState(false)
  const successTimer = useRef<ReturnType<typeof setTimeout> | null>(null)

  useEffect(() => {
    return () => {
      if (successTimer.current) clearTimeout(successTimer.current)
    }
  }, [])

  const handleClick = () => {
    setFeedback(null)
    setIsError(false)
    if (successTimer.current) {
      clearTimeout(successTimer.current)
      successTimer.current = null
    }
    setJustSucceeded(false)
    startTransition(async () => {
      const result = await onSyncAllBanks()
      if (!result.success) {
        setIsError(true)
        setFeedback(result.error ?? 'Sync failed')
        return
      }
      const data = result.data
      if (!data || data.connectionsSynced === 0) {
        setFeedback('No banks linked')
        return
      }
      if (data.transactionsInserted > 0) {
        setFeedback(`+${data.transactionsInserted} new`)
      } else {
        setFeedback(null)
      }
      setJustSucceeded(true)
      successTimer.current = setTimeout(() => {
        setJustSucceeded(false)
        successTimer.current = null
      }, SUCCESS_HOLD_MS)
    })
  }

  const showCheck = justSucceeded && !pending

  return (
    <div className="flex items-center gap-2">
      {feedback && (
        <span
          role="status"
          className={cn('text-[11px]', isError ? 'text-destructive' : 'text-muted-foreground')}
        >
          {feedback}
        </span>
      )}
      <Button
        variant="outline"
        size="sm"
        onClick={handleClick}
        disabled={pending}
        className={cn(
          'h-7 gap-1.5 px-2.5 text-[11px] transition-colors',
          showCheck &&
            'border-emerald-500/40 bg-emerald-500/10 text-emerald-700 hover:bg-emerald-500/15 hover:text-emerald-700 dark:text-emerald-300',
        )}
        aria-label="Sync all bank connections now"
      >
        {showCheck ? (
          <Check className="h-3.5 w-3.5" />
        ) : (
          <RefreshCw className={cn('h-3.5 w-3.5', pending && 'animate-spin')} />
        )}
        {pending ? 'Syncing…' : showCheck ? 'Synced' : 'Sync now'}
      </Button>
    </div>
  )
}
