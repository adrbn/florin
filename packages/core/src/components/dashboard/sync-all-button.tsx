'use client'

import { RefreshCw } from 'lucide-react'
import { useState, useTransition } from 'react'
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

export function SyncAllButton({ onSyncAllBanks }: SyncAllButtonProps) {
  const [pending, startTransition] = useTransition()
  const [feedback, setFeedback] = useState<string | null>(null)
  const [isError, setIsError] = useState(false)

  const handleClick = () => {
    setFeedback(null)
    setIsError(false)
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
      setFeedback(
        data.transactionsInserted > 0 ? `+${data.transactionsInserted} new` : 'Up to date',
      )
    })
  }

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
        className="h-7 gap-1.5 px-2.5 text-[11px]"
        aria-label="Sync all bank connections now"
      >
        <RefreshCw className={cn('h-3.5 w-3.5', pending && 'animate-spin')} />
        {pending ? 'Syncing…' : 'Sync now'}
      </Button>
    </div>
  )
}
