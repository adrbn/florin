'use client'

import { useState } from 'react'
import { Loader2 } from 'lucide-react'
import type { Aspsp } from '@florin/core/banking'
import { startBankConnection } from '@/server/actions/banking'

interface BankPickerProps {
  banks: ReadonlyArray<Aspsp>
  country: string
}

export function BankPicker({ banks, country }: BankPickerProps) {
  const [connecting, setConnecting] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  async function handleConnect(bank: Aspsp) {
    setConnecting(bank.name)
    setError(null)
    try {
      // Fixed redirect URL matching what's registered in Enable Banking.
      const redirectUrl = 'https://127.0.0.1:3847/api/banking/callback'
      const result = await startBankConnection({
        aspspName: bank.name,
        aspspCountry: bank.country ?? country,
        maxConsentDays: bank.maximum_consent_validity,
        redirectUrl,
      })
      if (!result.success) {
        setError(result.error ?? 'Failed to start bank connection')
        return
      }
      if (result.data?.url) {
        // Open the bank's SCA page in the system browser
        window.florin?.openExternal?.(result.data.url)
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Unknown error')
    } finally {
      setConnecting(null)
    }
  }

  return (
    <div className="space-y-3">
      {error && <p className="text-sm text-destructive">{error}</p>}
      {connecting && (
        <div className="flex items-center gap-2 rounded-md border border-primary/30 bg-primary/5 px-3 py-2 text-sm text-primary">
          <Loader2 className="h-4 w-4 animate-spin" />
          Opening {connecting} in your browser...
        </div>
      )}
      <ul className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
        {banks.map((bank) => (
          <li key={`${bank.country}-${bank.name}`}>
            <button
              type="button"
              onClick={() => handleConnect(bank)}
              disabled={connecting !== null}
              className="flex w-full items-center gap-3 rounded-md border border-input bg-background px-3 py-3 text-left shadow-sm transition-colors hover:bg-accent hover:text-accent-foreground disabled:opacity-50"
            >
              {bank.logo && (
                // biome-ignore lint/performance/noImgElement: external bank logos
                <img
                  src={bank.logo}
                  alt=""
                  width={28}
                  height={28}
                  className="h-7 w-7 shrink-0 rounded object-contain"
                />
              )}
              <span className="flex-1 text-sm font-medium">{bank.name}</span>
            </button>
          </li>
        ))}
      </ul>
    </div>
  )
}
