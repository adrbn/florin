'use client'

import { useState, useRef, useEffect, useCallback } from 'react'

interface PinInputProps {
  onSubmit: (pin: string) => Promise<boolean>
  length?: 4 | 5 | 6
}

export function PinInput({ onSubmit, length = 4 }: PinInputProps) {
  const [digits, setDigits] = useState<string[]>(Array(length).fill(''))
  const [error, setError] = useState(false)
  const [pending, setPending] = useState(false)
  const inputRef = useRef<HTMLInputElement | null>(null)

  useEffect(() => {
    inputRef.current?.focus()
  }, [])

  const submit = useCallback(
    async (pin: string) => {
      setPending(true)
      try {
        const ok = await onSubmit(pin)
        if (!ok) {
          setError(true)
          setDigits(Array(length).fill(''))
          setTimeout(() => inputRef.current?.focus(), 50)
        }
      } finally {
        setPending(false)
      }
    },
    [onSubmit, length],
  )

  function handleKeyDown(e: React.KeyboardEvent<HTMLInputElement>) {
    // Accept digits from both main row and numpad
    const digit = e.key.length === 1 && /^[0-9]$/.test(e.key) ? e.key : null

    if (digit) {
      e.preventDefault()
      setError(false)
      const next = [...digits]
      const idx = next.findIndex((d) => d === '')
      if (idx === -1) return
      next[idx] = digit
      setDigits(next)
      if (next.every((d) => d !== '')) {
        void submit(next.join(''))
      }
      return
    }

    if (e.key === 'Backspace') {
      e.preventDefault()
      setError(false)
      const next = [...digits]
      // Find last filled digit
      let idx = next.length - 1
      while (idx >= 0 && next[idx] === '') idx--
      if (idx >= 0) {
        next[idx] = ''
        setDigits(next)
      }
    }
  }

  return (
    <div className="flex flex-col items-center gap-6">
      {/* Single real input overlaid on dots — captures all keyboard events including numpad */}
      <div
        className="relative flex cursor-text gap-3"
        onClick={() => inputRef.current?.focus()}
      >
        {digits.map((digit, i) => (
          <div
            key={i}
            className={[
              'flex size-12 items-center justify-center rounded-lg border-2 text-xl font-semibold transition-colors',
              digit
                ? error
                  ? 'border-destructive bg-destructive/10 text-destructive'
                  : 'border-primary bg-primary/10 text-primary'
                : 'border-border bg-muted text-transparent',
            ].join(' ')}
          >
            {digit ? '●' : ''}
          </div>
        ))}
        <input
          ref={inputRef}
          type="text"
          inputMode="numeric"
          autoComplete="off"
          disabled={pending}
          aria-label="PIN code"
          className="absolute inset-0 cursor-text opacity-0"
          value={digits.join('')}
          onChange={() => {}}
          onKeyDown={handleKeyDown}
        />
      </div>

      {error && (
        <p className="text-sm font-medium text-destructive">Incorrect PIN. Try again.</p>
      )}
    </div>
  )
}
