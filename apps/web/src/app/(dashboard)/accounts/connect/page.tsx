/**
 * Bank picker page.
 *
 * Lists all ASPSPs (banks) Enable Banking can connect to in the user's
 * country, with La Banque Postale pinned to the top. Clicking a bank submits
 * a server-action form that calls Enable Banking POST /auth and redirects to
 * the bank's SCA page. After consent, the bank redirects back to
 * /api/banking/callback which finalizes everything.
 */
import Link from 'next/link'
import { Button, buttonVariants } from '@florin/core/components/ui/button'
import { Card, CardContent } from '@florin/core/components/ui/card'
import { listBanks, startBankConnection } from '@/server/actions/banking'
import { isEnableBankingConfigured } from '@/server/banking/enable-banking'

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

  if (!isEnableBankingConfigured()) {
    return (
      <div className="space-y-4">
        <h1 className="text-3xl font-bold tracking-tight">Connect a bank</h1>
        <Card>
          <CardContent className="py-12 text-center text-muted-foreground space-y-3">
            <p>Enable Banking is not configured.</p>
            <p className="text-xs">
              Set <code>ENABLE_BANKING_APP_ID</code> and{' '}
              <code>ENABLE_BANKING_PRIVATE_KEY_PATH</code> in <code>.env</code>, then restart the
              dev server.
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
          <h1 className="text-3xl font-bold tracking-tight">Connect a bank</h1>
          <p className="text-muted-foreground">
            Pick your bank to start the secure consent flow. You'll be redirected to your bank's
            login page to authorize Florin to read your accounts and transactions.
          </p>
        </div>
        <Link href="/accounts" className={buttonVariants({ variant: 'outline' })}>
          ← Back to accounts
        </Link>
      </div>

      <Card>
        <CardContent className="space-y-4 py-4">
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-sm font-medium text-muted-foreground">Country:</span>
            {COUNTRIES.map((c) => (
              <Link
                key={c.code}
                href={`/accounts/connect?country=${c.code}`}
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
            <ul className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
              {result.data.map((bank) => (
                <li key={`${bank.country}-${bank.name}`}>
                  <form action={startBankConnection}>
                    <input type="hidden" name="aspspName" value={bank.name} />
                    <input type="hidden" name="aspspCountry" value={bank.country} />
                    {bank.maximum_consent_validity !== undefined && (
                      <input
                        type="hidden"
                        name="maxConsentDays"
                        value={String(bank.maximum_consent_validity)}
                      />
                    )}
                    <Button
                      type="submit"
                      variant="outline"
                      className="w-full justify-start gap-3 h-auto py-3"
                    >
                      {bank.logo && (
                        // biome-ignore lint/performance/noImgElement: external bank logos
                        <img
                          src={bank.logo}
                          alt=""
                          width={28}
                          height={28}
                          className="h-7 w-7 rounded object-contain"
                        />
                      )}
                      <span className="flex-1 text-left text-sm font-medium">{bank.name}</span>
                    </Button>
                  </form>
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardContent className="space-y-2 py-4 text-xs text-muted-foreground">
          <p>
            <strong>How this works:</strong> Florin uses{' '}
            <a
              href="https://enablebanking.com"
              target="_blank"
              rel="noreferrer"
              className="underline"
            >
              Enable Banking
            </a>
            , a regulated PSD2 aggregator. When you click a bank, you'll be sent to that bank's real
            login page (not a Florin form). After you authenticate, the bank shares read-only access
            tokens with Florin via Enable Banking. Florin never sees your bank password.
          </p>
          <p>
            Consent expires after 90–180 days depending on the bank (PSD2 limit). You'll see a
            warning banner here when re-authorization is needed.
          </p>
        </CardContent>
      </Card>
    </div>
  )
}
