import Link from 'next/link'
import { buttonVariants } from '@florin/core/components/ui/button'
import { Card, CardContent } from '@florin/core/components/ui/card'
import { isEnableBankingConfigured, listBanks } from '@/server/actions/banking'
import { BankPicker } from '@/components/bank-picker'

interface ConnectPageProps {
  searchParams: Promise<{ country?: string }>
}

const COUNTRIES: ReadonlyArray<{ code: string; label: string }> = [
  { code: 'FR', label: 'France' },
  { code: 'BE', label: 'Belgium' },
  { code: 'DE', label: 'Germany' },
  { code: 'ES', label: 'Spain' },
  { code: 'IT', label: 'Italy' },
  { code: 'NL', label: 'Netherlands' },
  { code: 'PT', label: 'Portugal' },
  { code: 'LU', label: 'Luxembourg' },
]

export default async function ConnectBankPage({ searchParams }: ConnectPageProps) {
  const params = await searchParams
  const country = params.country ?? 'FR'
  const configured = await isEnableBankingConfigured()

  if (!configured) {
    return (
      <div className="space-y-4">
        <h1 className="text-2xl font-bold tracking-tight">Connect a bank</h1>
        <Card>
          <CardContent className="space-y-3 py-12 text-center text-muted-foreground">
            <p>Enable Banking is not configured.</p>
            <p className="text-xs">
              Go to <strong>Settings &rarr; Bank Sync</strong> to add your Enable Banking credentials.
            </p>
          </CardContent>
        </Card>
      </div>
    )
  }

  const result = await listBanks(country)

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">Connect a bank</h1>
          <p className="text-xs text-muted-foreground">
            Pick your bank to start the secure consent flow. You&apos;ll be redirected to your
            bank&apos;s login page to authorize Florin.
          </p>
        </div>
        <Link href={'/accounts' as never} className={buttonVariants({ variant: 'outline', size: 'sm' })}>
          &larr; Back
        </Link>
      </div>

      <Card>
        <CardContent className="space-y-4 py-4">
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-sm font-medium text-muted-foreground">Country:</span>
            {COUNTRIES.map((c) => (
              <Link
                key={c.code}
                href={`/accounts/connect?country=${c.code}` as never}
                className={`rounded-full border px-3 py-1 text-xs ${
                  c.code === country
                    ? 'border-primary bg-primary/10 text-primary'
                    : 'border-border text-muted-foreground hover:bg-muted'
                }`}
              >
                {c.label}
              </Link>
            ))}
          </div>

          {!result.success && (
            <p className="text-sm text-destructive">Failed to load banks: {result.error}</p>
          )}

          {result.success && result.data && result.data.length === 0 && (
            <p className="text-sm text-muted-foreground">
              No banks found for {country}. Try another country.
            </p>
          )}

          {result.success && result.data && result.data.length > 0 && (
            <BankPicker banks={result.data} country={country} />
          )}
        </CardContent>
      </Card>

      <Card>
        <CardContent className="space-y-2 py-4 text-xs text-muted-foreground">
          <p>
            <strong>How this works:</strong> Florin uses{' '}
            <a href="https://enablebanking.com" target="_blank" rel="noreferrer" className="underline">
              Enable Banking
            </a>
            , a regulated PSD2 aggregator. When you click a bank, your system browser opens the
            bank&apos;s real login page (not a Florin form). After you authenticate, the bank shares
            read-only access tokens with Florin. Florin never sees your bank password.
          </p>
          <p>
            Consent expires after 90&ndash;180 days depending on the bank (PSD2 limit). You&apos;ll
            see a warning on the Accounts page when re-authorization is needed.
          </p>
        </CardContent>
      </Card>
    </div>
  )
}
