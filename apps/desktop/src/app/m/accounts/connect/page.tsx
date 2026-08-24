import { ConnectScreen } from '@florin/core/components/v2/screens/connect'
import { queries } from '@/db/client'
import {
  isEnableBankingConfigured,
  listBanks,
  startBankConnection,
  syncBankConnection,
} from '@/server/actions/banking'
import { ConnectClient } from './connect-client'

export const dynamic = 'force-dynamic'

const SUPPORTED = new Set(['FR', 'BE', 'DE', 'ES', 'IT', 'NL', 'PT', 'LU'])

export default async function V2Connect({
  searchParams,
}: {
  searchParams: Promise<{ country?: string }>
}) {
  const { country: raw } = await searchParams
  const country = raw && SUPPORTED.has(raw.toUpperCase()) ? raw.toUpperCase() : 'FR'

  const configured = await isEnableBankingConfigured()
  const [banksResult, connections] = await Promise.all([
    configured
      ? listBanks(country)
      : Promise.resolve({ success: false as const, data: undefined }),
    queries.listBankConnections(),
  ])

  return (
    <ConnectClient
      configured={Boolean(configured)}
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
        const res = await startBankConnection({
          aspspName: bank.name,
          aspspCountry: bank.country,
          maxConsentDays: bank.maxConsentDays,
          // Fixed redirect registered in the Enable Banking console.
          redirectUrl: 'https://127.0.0.1:3847/api/banking/callback',
        })
        return { success: res.success, url: res.data?.url, error: res.error }
      }}
      onSync={async (connectionId: string) => {
        'use server'
        await syncBankConnection(connectionId)
      }}
    />
  )
}
