import { SettingsScreen } from '@florin/core/components/v2/screens/settings'
import { isEnableBankingConfigured } from '@/server/banking/enable-banking'
import pkg from '../../../../package.json'
import { SignOutButton } from '../sign-out-button'

export const dynamic = 'force-dynamic'

export default function V2Settings() {
  return (
    <SettingsScreen
      version={pkg.version}
      bankSyncConfigured={isEnableBankingConfigured()}
      localeEndpoint="/api/locale"
      signOut={<SignOutButton />}
    />
  )
}
