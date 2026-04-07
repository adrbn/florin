import type { Metadata } from 'next'
import './globals.css'

export const metadata: Metadata = {
  title: 'Florin',
  description: 'Personal finance dashboard',
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  )
}
