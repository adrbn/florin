import type { Viewport } from 'next'
import { headers } from 'next/headers'
import '@florin/core/components/v2/theme/v2.css'
import { V2Chrome } from '@florin/core/components/v2/shell/chrome'
import { V2I18nProvider } from '@florin/core/components/v2/i18n/context'
import { V2ConfigProvider } from '@florin/core/components/v2/lib/config'
import { mapAccount, mapCategories } from '@florin/core/components/v2/lib/map'
import { queries } from '@/db/client'
import { getUserLocale } from '@/lib/locale'
import { addTransaction, addTransfer, countNeedsReview } from '@/server/actions/transactions'
import { syncAllBanks } from '@/server/actions/banking'
import pkg from '../../../package.json'

export const dynamic = 'force-dynamic'

// The v2 surface is phone-first: cover the notch, no user zoom fighting the
// sticky chrome, and a theme colour that matches the Obsidian background so
// iOS paints the status bar the same shade as the app.
export const viewport: Viewport = {
  width: 'device-width',
  initialScale: 1,
  viewportFit: 'cover',
  themeColor: [
    { media: '(prefers-color-scheme: light)', color: '#fbfbfd' },
    { media: '(prefers-color-scheme: dark)', color: '#0d0e12' },
  ],
}

export default async function V2Layout({ children }: { children: React.ReactNode }) {
  /*
   * The native iOS client appends `FlorinApp/<version>` to its user agent. When
   * it is the host, it supplies the tab bar and the navigation chrome itself,
   * so this layout must not draw a second set on top of it.
   */
  const requestHeaders = await headers()
  const chromeless = (requestHeaders.get('user-agent') ?? '').includes('FlorinApp/')

  const [locale, accounts, groups, reviewCount] = await Promise.all([
    getUserLocale(),
    queries.listAccounts(),
    queries.listCategoriesByGroup(),
    countNeedsReview(),
  ])

  return (
    <V2ConfigProvider locale={locale} currency="EUR">
      <V2I18nProvider locale={locale}>
        <div data-florin-v2 className="v2-app" data-chromeless={chromeless || undefined}>
          <V2Chrome
            accounts={accounts.map(mapAccount)}
            categories={mapCategories(groups)}
            reviewCount={reviewCount}
            version={pkg.version}
            chromeless={chromeless}
            localeEndpoint="/api/settings/locale"
            actions={{ addTransaction, addTransfer, syncAllBanks }}
          >
            {children}
          </V2Chrome>
        </div>
      </V2I18nProvider>
    </V2ConfigProvider>
  )
}
