import type { Metadata } from 'next'
import './globals.css'
import { ThemeProvider } from '@florin/core/components/theme/theme-provider'

export const metadata: Metadata = {
  title: 'Florin',
  description: 'Your finances, your machine.',
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  // `suppressHydrationWarning` is required by next-themes because the
  // provider writes the `class` attribute to <html> on the client before
  // React hydrates, producing a harmless mismatch otherwise.
  return (
    <html lang="en" suppressHydrationWarning>
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
