import type { LucideIcon } from 'lucide-react'
import Link from 'next/link'
import type { ComponentProps } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { cn } from '@/lib/utils'

type KpiHref = ComponentProps<typeof Link>['href']

export type KpiTone = 'default' | 'positive' | 'negative' | 'warning'

interface KpiCardProps {
  title: string
  value: string
  hint?: string
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
        'gap-1 py-3',
        clickable &&
          'transition-colors hover:bg-muted/40 group-focus-visible:ring-2 group-focus-visible:ring-ring',
      )}
    >
      <CardHeader className="flex flex-row items-center justify-between space-y-0 px-4 py-0">
        <CardTitle className="text-xs font-medium text-muted-foreground">{title}</CardTitle>
        {Icon ? <Icon className="h-3.5 w-3.5 text-muted-foreground" /> : null}
      </CardHeader>
      <CardContent className="px-4 py-0">
        <p className={cn('text-2xl font-bold tracking-tight tabular-nums', TONE_CLASSES[tone])}>
          {value}
        </p>
        {hint ? <p className="mt-0.5 truncate text-xs text-muted-foreground">{hint}</p> : null}
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
