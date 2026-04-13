import type { Metadata } from 'next'
import './globals.css'
import { Geist } from 'next/font/google'
import { eq } from 'drizzle-orm'
import { ThemeProvider } from '@florin/core/components/theme/theme-provider'
import { I18nProvider } from '@florin/core/i18n/context'
import { setCurrencyConfig } from '@florin/core/lib/format'
import { cn } from '@florin/core/lib/utils'
import { db } from '@/db/client'
import { settings } from '@/db/schema'

const geist = Geist({ subsets: ['latin'], variable: '--font-sans' })

export const dynamic = 'force-dynamic'

export const metadata: Metadata = {
  title: 'Florin',
  description: 'Your finances, your machine.',
}

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  let locale = 'fr-FR'
  let currency = 'EUR'
  try {
    const [localeRow, currencyRow] = await Promise.all([
      db.select().from(settings).where(eq(settings.key, 'user_locale')).get(),
      db.select().from(settings).where(eq(settings.key, 'user_currency')).get(),
    ])
    if (localeRow?.value) locale = localeRow.value
    if (currencyRow?.value) currency = currencyRow.value
  } catch { /* settings table may not exist yet */ }

  // Update the global formatter so server components and static imports use
  // the user's chosen currency without needing a React context.
  setCurrencyConfig(locale, currency)

  // `suppressHydrationWarning` is required by next-themes because the
  // provider writes the `class` attribute to <html> on the client before
  // React hydrates, producing a harmless mismatch otherwise.
  return (
    <html lang="en" className={cn('font-sans', geist.variable)} suppressHydrationWarning>
      <body className={geist.className}>
        <ThemeProvider
          attribute="class"
          defaultTheme="system"
          enableSystem
          disableTransitionOnChange
        >
          <I18nProvider locale="en">
            {children}
          </I18nProvider>
        </ThemeProvider>
      </body>
    </html>
  )
}
