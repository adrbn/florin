import type { LucideIcon } from 'lucide-react'
import Link from 'next/link'
import type { ComponentProps, ReactNode } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { cn } from '@/lib/utils'

type KpiHref = ComponentProps<typeof Link>['href']

export type KpiTone = 'default' | 'positive' | 'negative' | 'warning'

interface KpiCardProps {
  title: string
  value: string
  /**
   * Secondary line shown under the headline number. Accepts a ReactNode
   * (not just a string) so callers can render multi-line breakdowns like
   * "Gross …" on one row and "− Debt …" on the next without having to
   * reach into the card internals.
   */
  hint?: ReactNode
  icon?: LucideIcon
  tone?: KpiTone
  /**
   * Optional destination. When provided, the whole card becomes an anchor,
   * so users can click a KPI to drill into the transactions that add up to
   * it. Derived from `next/link`'s own `href` prop so we keep typedRoutes
   * safety for both string and UrlObject callers.
   */
  href?: KpiHref
}

const TONE_CLASSES: Record<KpiTone, string> = {
  default: 'text-foreground',
  positive: 'text-emerald-600 dark:text-emerald-400',
  negative: 'text-destructive',
  warning: 'text-amber-600 dark:text-amber-400',
}

export function KpiCard({ title, value, hint, icon: Icon, tone = 'default', href }: KpiCardProps) {
  const clickable = href !== undefined
  const card = (
    <Card
      className={cn(
        'gap-2 py-5',
        clickable &&
          'transition-colors hover:bg-muted/40 group-focus-visible:ring-2 group-focus-visible:ring-ring',
      )}
    >
      <CardHeader className="flex flex-row items-center justify-between space-y-0 px-6 py-0">
        <CardTitle className="text-sm font-medium text-muted-foreground">{title}</CardTitle>
        {Icon ? <Icon className="h-4 w-4 text-muted-foreground" /> : null}
      </CardHeader>
      <CardContent className="px-6 py-0">
        <p className={cn('text-4xl font-bold tracking-tight tabular-nums', TONE_CLASSES[tone])}>
          {value}
        </p>
        {hint ? <div className="mt-1.5 text-[11px] text-muted-foreground">{hint}</div> : null}
      </CardContent>
    </Card>
  )
  if (clickable) {
    return (
      <Link
        href={href}
        className="group block rounded-xl focus:outline-none focus-visible:outline-none"
        aria-label={`${title} — view breakdown`}
      >
        {card}
      </Link>
    )
  }
  return card
}
