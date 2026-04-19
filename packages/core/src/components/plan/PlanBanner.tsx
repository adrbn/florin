'use client'

import { useEffect, useState } from 'react'
import { ChevronDown, ChevronRight, Info } from 'lucide-react'
import type { MonthPlan } from '@florin/core/types'
import { formatCurrency } from '@florin/core/lib/format'

interface PlanBannerProps {
  plan: MonthPlan
  currency: string
}

const STORAGE_KEY = 'florin:plan-banner-expanded'

// currency is unused — formatCurrency reads from setCurrencyConfig singleton
export function PlanBanner({ plan, currency: _currency }: PlanBannerProps) {
  // Collapsed by default; user can reveal. Persisted in localStorage.
  const [expanded, setExpanded] = useState(false)

  useEffect(() => {
    try {
      const raw = window.localStorage.getItem(STORAGE_KEY)
      if (raw === '1') setExpanded(true)
    } catch {
      // ignore (SSR / private mode)
    }
  }, [])

  const toggle = () => {
    setExpanded((v) => {
      const next = !v
      try {
        window.localStorage.setItem(STORAGE_KEY, next ? '1' : '0')
      } catch {
        // ignore
      }
      return next
    })
  }

  const overAssigned = plan.readyToAssign < 0
  const banner = overAssigned
    ? {
        text: `${formatCurrency(plan.readyToAssign)} Assigned Too Much`,
        className: 'bg-red-500 text-red-50',
      }
    : plan.readyToAssign > 0
      ? {
          text: `${formatCurrency(plan.readyToAssign)} Ready to Assign`,
          className: 'bg-emerald-500 text-emerald-50',
        }
      : {
          text: 'All assigned',
          className: 'bg-muted text-muted-foreground',
        }

  return (
    <div className="px-4 py-2 border-b border-border flex items-center gap-2">
      <button
        type="button"
        onClick={toggle}
        aria-expanded={expanded}
        aria-label={expanded ? 'Hide plan status' : 'Show plan status'}
        className="inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground shrink-0"
      >
        {expanded ? <ChevronDown size={14} /> : <ChevronRight size={14} />}
        <Info size={14} />
        <span className="hidden sm:inline">Plan status</span>
      </button>

      {expanded ? (
        <div
          className={`flex-1 min-w-0 rounded-full px-3 py-1.5 text-sm font-semibold flex items-center gap-2 ${banner.className}`}
          data-testid="plan-banner"
        >
          <span className="truncate">{banner.text}</span>
          <span className="ml-auto text-xs font-normal opacity-80 truncate hidden sm:inline">
            Income {formatCurrency(plan.income)} · Assigned {formatCurrency(plan.totalAssigned)}
          </span>
        </div>
      ) : (
        <div className="flex-1" />
      )}

      {plan.overspentCount > 0 ? (
        <span className="inline-flex items-center rounded-full bg-red-500/15 text-red-500 border border-red-500/30 px-2 py-0.5 text-xs font-medium shrink-0">
          {plan.overspentCount} overspent
        </span>
      ) : null}
    </div>
  )
}
