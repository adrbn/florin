'use client'

import { useState, useRef, useEffect } from 'react'

interface PinInputProps {
  onSubmit: (pin: string) => Promise<boolean>
  length?: 4 | 5 | 6
}

export function PinInput({ onSubmit, length = 4 }: PinInputProps) {
  const [digits, setDigits] = useState<string[]>(Array(length).fill(''))
  const [error, setError] = useState(false)
  const [pending, setPending] = useState(false)
  const inputsRef = useRef<(HTMLInputElement | null)[]>([])

  // Focus the first empty slot on mount
  useEffect(() => {
    inputsRef.current[0]?.focus()
  }, [])

  function handleChange(index: number, value: string) {
    const digit = value.replace(/\D/g, '').slice(-1)
    const next = [...digits]
    next[index] = digit
    setDigits(next)
    setError(false)

    if (digit && index < length - 1) {
      inputsRef.current[index + 1]?.focus()
    }

    // Auto-submit when all digits filled
    const filled = next.every((d) => d !== '')
    if (filled) {
      void submit(next.join(''))
    }
  }

  function handleKeyDown(index: number, e: React.KeyboardEvent<HTMLInputElement>) {
    if (e.key === 'Backspace' && !digits[index] && index > 0) {
      inputsRef.current[index - 1]?.focus()
    }
  }

  async function submit(pin: string) {
    setPending(true)
    try {
      const ok = await onSubmit(pin)
      if (!ok) {
        setError(true)
        setDigits(Array(length).fill(''))
        setTimeout(() => {
          inputsRef.current[0]?.focus()
        }, 50)
      }
    } finally {
      setPending(false)
    }
  }

  return (
    <div className="flex flex-col items-center gap-6">
      <div className="flex gap-3">
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
      </div>

      {/* Hidden inputs for focus management and keyboard input */}
      <div className="sr-only flex gap-2">
        {digits.map((digit, i) => (
          <input
            key={i}
            ref={(el) => {
              inputsRef.current[i] = el
            }}
            type="text"
            inputMode="numeric"
            pattern="[0-9]*"
            maxLength={1}
            value={digit}
            disabled={pending}
            aria-label={`PIN digit ${i + 1}`}
            onChange={(e) => handleChange(i, e.target.value)}
            onKeyDown={(e) => handleKeyDown(i, e)}
          />
        ))}
      </div>

      {error && (
        <p className="text-sm font-medium text-destructive">Incorrect PIN. Try again.</p>
      )}
    </div>
  )
}
