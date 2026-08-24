import { SettingsScreen } from '@florin/core/components/v2/screens/settings'
import { isEnableBankingConfigured } from '@/server/actions/banking'
import pkg from '../../../../package.json'

export const dynamic = 'force-dynamic'

export default async function V2Settings() {
  const configured = await isEnableBankingConfigured()
  return (
    <SettingsScreen
      version={pkg.version}
      bankSyncConfigured={Boolean(configured)}
      localeEndpoint="/api/settings/locale"
    />
  )
}
