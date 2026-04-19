import type { Metadata } from 'next'
import './globals.css'
import { Geist } from 'next/font/google'
import { ThemeProvider } from '@florin/core/components/theme/theme-provider'
import { I18nProvider } from '@florin/core/i18n/context'
import { PrivacyProvider, PrivacyBodyClass } from '@florin/core/privacy'
import { cn } from '@/lib/utils'
import { getUserLocale } from '@/lib/locale'

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

export const viewport = {
  themeColor: '#3b82f6',
}

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  const locale = await getUserLocale()
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
