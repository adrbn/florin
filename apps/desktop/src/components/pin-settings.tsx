'use client'

import { useState } from 'react'
import { PinInput } from './pin-input'
import { setPin, removePin } from '@/server/actions/pin'

interface PinSettingsProps {
  pinEnabled: boolean
}

type View = 'idle' | 'set-pin' | 'confirm-remove'

export function PinSettings({ pinEnabled }: PinSettingsProps) {
  const [enabled, setEnabled] = useState(pinEnabled)
  const [view, setView] = useState<View>('idle')
  const [status, setStatus] = useState<string | null>(null)

  async function handleSetPin(pin: string): Promise<boolean> {
    try {
      await setPin(pin)
      setEnabled(true)
      setView('idle')
      setStatus('PIN set successfully.')
      return true
    } catch {
      return false
    }
  }

  async function handleRemovePin() {
    try {
      await removePin()
      setEnabled(false)
      setView('idle')
      setStatus('PIN removed.')
    } catch {
      setStatus('Failed to remove PIN.')
    }
  }

  if (view === 'set-pin') {
    return (
      <div className="space-y-4">
        <p className="text-sm text-muted-foreground">
          Choose a {enabled ? 'new' : ''} 4-digit PIN. You will be prompted for it each time you
          open Florin.
        </p>
        <PinInput onSubmit={handleSetPin} />
        <button
          type="button"
          onClick={() => setView('idle')}
          className="text-xs text-muted-foreground underline underline-offset-2 hover:text-foreground"
        >
          Cancel
        </button>
      </div>
    )
  }

  if (view === 'confirm-remove') {
    return (
      <div className="space-y-3">
        <p className="text-sm text-muted-foreground">
          Remove the PIN? Florin will open without a lock screen.
        </p>
        <div className="flex gap-2">
          <button
            type="button"
            onClick={handleRemovePin}
            className="rounded-md bg-destructive/10 px-3 py-1.5 text-sm font-medium text-destructive hover:bg-destructive/20"
          >
            Remove PIN
          </button>
          <button
            type="button"
            onClick={() => setView('idle')}
            className="rounded-md border border-border px-3 py-1.5 text-sm font-medium hover:bg-muted"
          >
            Cancel
          </button>
        </div>
      </div>
    )
  }

  return (
    <div className="space-y-3">
      {status && (
        <p className="text-xs text-muted-foreground">{status}</p>
      )}
      <p className="text-sm text-muted-foreground">
        {enabled
          ? 'PIN protection is active. Florin prompts for a PIN on each launch.'
          : 'No PIN set. Florin opens without a lock screen.'}
      </p>
      <div className="flex gap-2">
        <button
          type="button"
          onClick={() => { setStatus(null); setView('set-pin') }}
          className="rounded-md border border-border px-3 py-1.5 text-sm font-medium hover:bg-muted"
        >
          {enabled ? 'Change PIN' : 'Set PIN'}
        </button>
        {enabled && (
          <button
            type="button"
            onClick={() => { setStatus(null); setView('confirm-remove') }}
            className="rounded-md bg-destructive/10 px-3 py-1.5 text-sm font-medium text-destructive hover:bg-destructive/20"
          >
            Remove PIN
          </button>
        )}
      </div>
    </div>
  )
}
