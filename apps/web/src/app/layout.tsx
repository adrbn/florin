import type { Metadata } from 'next'
import './globals.css'
import { Geist } from 'next/font/google'
import { ThemeProvider } from '@florin/core/components/theme/theme-provider'
import { cn } from '@/lib/utils'

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

export default function RootLayout({ children }: { children: React.ReactNode }) {
  // `suppressHydrationWarning` is required by next-themes because the
  // provider writes the `class` attribute to <html> on the client before
  // React hydrates, producing a harmless mismatch otherwise.
  return (
    <html lang="en" className={cn('font-sans', geist.variable)} suppressHydrationWarning>
      <body>
        <ThemeProvider
          attribute="class"
          defaultTheme="system"
          enableSystem
          disableTransitionOnChange
        >
          {children}
        </ThemeProvider>
      </body>
    </html>
  )
}
