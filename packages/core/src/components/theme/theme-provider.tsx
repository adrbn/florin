'use client'

import { ThemeProvider as NextThemesProvider, type ThemeProviderProps } from 'next-themes'

/**
 * Client-side wrapper around `next-themes` so the root server layout can
 * opt in to theming without turning itself into a client component. The
 * provider writes the `class="dark"` (or light) attribute on `<html>`,
 * which our Tailwind tokens in `globals.css` already key off.
 */
export function ThemeProvider({ children, ...props }: ThemeProviderProps) {
  return <NextThemesProvider {...props}>{children}</NextThemesProvider>
}
