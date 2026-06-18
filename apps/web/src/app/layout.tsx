import type { Metadata, Viewport } from 'next'
import './globals.css'
import { Geist } from 'next/font/google'
import { ThemeProvider } from '@florin/core/components/theme/theme-provider'
import { I18nProvider } from '@florin/core/i18n/context'
import { setCurrencyConfig } from '@florin/core/lib/format'
import { PrivacyProvider, PrivacyBodyClass } from '@florin/core/privacy'
import { cn } from '@/lib/utils'
import { APP_CURRENCY, getUserLocale } from '@/lib/locale'

const geist = Geist({ subsets: ['latin'], variable: '--font-sans' })

export const metadata: Metadata = {
  title: 'Florin',
  description: 'Personal finance dashboard',
  manifest: '/manifest.webmanifest',
  appleWebApp: {
    capable: true,
    statusBarStyle: 'black-translucent',
    title: 'Florin',
  },
}

export const viewport: Viewport = {
  themeColor: '#3b82f6',
  width: 'device-width',
  initialScale: 1,
  viewportFit: 'cover',
}

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  const locale = await getUserLocale()

  // Update the global currency formatter so server components and static
  // imports honour the deploy-time currency (APP_CURRENCY, default EUR) and
  // the user's locale, without needing a React context. Mirrors desktop.
  setCurrencyConfig(locale, APP_CURRENCY)

  // `suppressHydrationWarning` is required by next-themes because the
  // provider writes the `class` attribute to <html> on the client before
  // React hydrates, producing a harmless mismatch otherwise.
  return (
    <html lang={locale} className={cn('font-sans', geist.variable)} suppressHydrationWarning>
      <body>
        <ThemeProvider
          attribute="class"
          defaultTheme="system"
          enableSystem
          disableTransitionOnChange
        >
          <I18nProvider locale={locale}>
            <PrivacyProvider>
              <PrivacyBodyClass />
              {children}
            </PrivacyProvider>
          </I18nProvider>
        </ThemeProvider>
      </body>
    </html>
  )
}
