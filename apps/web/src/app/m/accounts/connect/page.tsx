import { ConnectScreen } from '@florin/core/components/v2/screens/connect'
import { queries } from '@/db/client'
import { listBanks, startBankConnection, syncBankConnection } from '@/server/actions/banking'
import { isEnableBankingConfigured } from '@/server/banking/enable-banking'

export const dynamic = 'force-dynamic'

const SUPPORTED = new Set(['FR', 'BE', 'DE', 'ES', 'IT', 'NL', 'PT', 'LU'])

export default async function V2Connect({
  searchParams,
}: {
  searchParams: Promise<{ country?: string }>
}) {
  const { country: raw } = await searchParams
  const country = raw && SUPPORTED.has(raw.toUpperCase()) ? raw.toUpperCase() : 'FR'

  const configured = isEnableBankingConfigured()
  const [banksResult, connections] = await Promise.all([
    configured
      ? listBanks(country)
      : Promise.resolve({ success: false as const, data: undefined }),
    queries.listBankConnections(),
  ])

  return (
    <ConnectScreen
      configured={configured}
      country={country}
      banks={(banksResult.data ?? []).map((b) => ({
        name: b.name,
        country: b.country ?? country,
        logo: b.logo ?? null,
        maxConsentDays: b.maximum_consent_validity,
      }))}
      connections={connections.map((c) => ({
        id: c.id,
        aspspName: c.aspspName,
        status: c.status,
        validUntil: c.validUntil.toISOString(),
        lastSyncedAt: c.lastSyncedAt ? c.lastSyncedAt.toISOString() : null,
        lastSyncError: c.lastSyncError,
      }))}
      onStart={async (bank) => {
        'use server'
        /*
         * The web action takes FormData and calls `redirect()` itself — the
         * redirect URL is a deploy-time env var, not something the caller
         * chooses, and Next turns the throw into a client navigation. So this
         * never actually returns; the `{ success: true }` below exists only to
         * satisfy the shared prop type, which the desktop build does use.
         */
        const form = new FormData()
        form.set('aspspName', bank.name)
        form.set('aspspCountry', bank.country)
        if (bank.maxConsentDays !== undefined) {
          form.set('maxConsentDays', String(bank.maxConsentDays))
        }
        await startBankConnection(form)
        return { success: true }
      }}
      onSync={async (connectionId: string) => {
        'use server'
        await syncBankConnection(connectionId)
      }}
    />
  )
}
