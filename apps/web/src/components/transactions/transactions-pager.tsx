'use client'

import { ChevronLeft, ChevronRight, ChevronsLeft, ChevronsRight } from 'lucide-react'
import type { Route } from 'next'
import { usePathname, useRouter, useSearchParams } from 'next/navigation'
import { useTransition } from 'react'
import { Button } from '@/components/ui/button'

interface TransactionsPagerProps {
  page: number
  pageSize: number
  totalCount: number
}

/**
 * Pager for the Transactions page. Uses URL `page` searchParam so bookmarks
 * and shared links preserve position, and `router.replace` so bouncing
 * between pages doesn't pollute history with an entry per click.
 *
 * Renders "Showing X–Y of Z" on the left and first/prev/next/last on the
 * right. All five controls are disabled when they'd no-op so the user never
 * wonders whether a click "did something".
 */
export function TransactionsPager({ page, pageSize, totalCount }: TransactionsPagerProps) {
  const router = useRouter()
  const pathname = usePathname()
  const searchParams = useSearchParams()
  const [, startNavTransition] = useTransition()

  const totalPages = Math.max(1, Math.ceil(totalCount / pageSize))
  const clampedPage = Math.min(Math.max(1, page), totalPages)
  const firstRow = totalCount === 0 ? 0 : (clampedPage - 1) * pageSize + 1
  const lastRow = Math.min(clampedPage * pageSize, totalCount)

  const goTo = (nextPage: number) => {
    const target = Math.min(Math.max(1, nextPage), totalPages)
    if (target === clampedPage) return
    const next = new URLSearchParams(searchParams.toString())
    if (target === 1) next.delete('page')
    else next.set('page', String(target))
    const query = next.toString()
    const href = (query ? `${pathname}?${query}` : pathname) as Route
    startNavTransition(() => router.replace(href, { scroll: false }))
  }

  if (totalCount === 0) return null

  return (
    <div className="flex flex-wrap items-center justify-between gap-2 border-t border-border/60 bg-muted/20 px-4 py-2 text-xs text-muted-foreground">
      <div>
        Showing{' '}
        <span className="font-medium text-foreground tabular-nums">{firstRow.toLocaleString('fr-FR')}</span>–
        <span className="font-medium text-foreground tabular-nums">{lastRow.toLocaleString('fr-FR')}</span>{' '}
        of <span className="font-medium text-foreground tabular-nums">{totalCount.toLocaleString('fr-FR')}</span>
      </div>
      <div className="flex items-center gap-1">
        <Button
          type="button"
          variant="outline"
          size="sm"
          className="h-7 px-2"
          disabled={clampedPage <= 1}
          onClick={() => goTo(1)}
          aria-label="First page"
        >
          <ChevronsLeft className="h-3.5 w-3.5" />
        </Button>
        <Button
          type="button"
          variant="outline"
          size="sm"
          className="h-7 px-2"
          disabled={clampedPage <= 1}
          onClick={() => goTo(clampedPage - 1)}
          aria-label="Previous page"
        >
          <ChevronLeft className="h-3.5 w-3.5" />
        </Button>
        <span className="px-2 tabular-nums">
          Page <span className="font-medium text-foreground">{clampedPage}</span> of{' '}
          <span className="font-medium text-foreground">{totalPages}</span>
        </span>
        <Button
          type="button"
          variant="outline"
          size="sm"
          className="h-7 px-2"
          disabled={clampedPage >= totalPages}
          onClick={() => goTo(clampedPage + 1)}
          aria-label="Next page"
        >
          <ChevronRight className="h-3.5 w-3.5" />
        </Button>
        <Button
          type="button"
          variant="outline"
          size="sm"
          className="h-7 px-2"
          disabled={clampedPage >= totalPages}
          onClick={() => goTo(totalPages)}
          aria-label="Last page"
        >
          <ChevronsRight className="h-3.5 w-3.5" />
        </Button>
      </div>
    </div>
  )
}
