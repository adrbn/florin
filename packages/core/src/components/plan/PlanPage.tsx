'use client'

import { useState, useTransition } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import { toast } from 'sonner'
import type { ActionResult, MonthPlan, SetCategoryAssignedInput } from '@florin/core/types'
import { MonthPicker } from './MonthPicker'
import { PlanBanner } from './PlanBanner'
import { PlanGroup } from './PlanGroup'

interface PlanPageProps {
  plan: MonthPlan
  currency: string
  onSetAssigned: (input: SetCategoryAssignedInput) => Promise<ActionResult>
}

export function PlanPage({ plan, currency, onSetAssigned }: PlanPageProps) {
  const router = useRouter()
  const searchParams = useSearchParams()
  const [, startTransition] = useTransition()
  const [optimistic, setOptimistic] = useState<MonthPlan>(plan)

  // If the server plan changes (e.g. after navigating months), reset optimistic state.
  if (optimistic !== plan && optimistic.year === plan.year && optimistic.month === plan.month) {
    // same month, server refreshed — ignore (our optimistic wins until next nav)
  }
  if (optimistic.year !== plan.year || optimistic.month !== plan.month) {
    setOptimistic(plan)
  }

  function navigate(year: number, month: number) {
    const params = new URLSearchParams(searchParams?.toString() ?? '')
    params.set('month', `${year}-${String(month).padStart(2, '0')}`)
    router.push(`?${params.toString()}`)
  }

  async function handleAssignedChange(categoryId: string, amount: number) {
    // Optimistic update: recompute the in-memory plan with the new assigned.
    setOptimistic((prev) => recomputeWithAssigned(prev, categoryId, amount))

    const result = await onSetAssigned({
      year: plan.year,
      month: plan.month,
      categoryId,
      amount,
    })

    if (!result.success) {
      toast.error(result.error ?? 'Failed to save assignment')
      // Revert: ask Next.js to re-fetch the server plan.
      startTransition(() => router.refresh())
      return
    }
    startTransition(() => router.refresh())
  }

  return (
    <div className="flex flex-col h-full min-h-0">
      <MonthPicker year={optimistic.year} month={optimistic.month} onChange={navigate} />
      <PlanBanner plan={optimistic} currency={currency} />
      <div className="flex-1 overflow-y-auto">
        {optimistic.groups.map((g) => (
          <PlanGroup
            key={g.id}
            group={g}
            currency={currency}
            onAssignedChange={handleAssignedChange}
          />
        ))}
      </div>
    </div>
  )
}

function recomputeWithAssigned(plan: MonthPlan, categoryId: string, newAmount: number): MonthPlan {
  let totalAssigned = 0
  let overspentCount = 0
  const groups = plan.groups.map((g) => {
    let gAssigned = 0
    let gAvailable = 0
    let gOverspent = 0
    const categories = g.categories.map((c) => {
      const assigned = c.id === categoryId ? newAmount : c.assigned
      const available = assigned - c.spent
      gAssigned += assigned
      gAvailable += available
      if (available < 0) gOverspent += 1
      return { ...c, assigned, available }
    })
    totalAssigned += gAssigned
    overspentCount += gOverspent
    return { ...g, categories, assigned: gAssigned, available: gAvailable, overspentCount: gOverspent }
  })
  return {
    ...plan,
    groups,
    totalAssigned,
    readyToAssign: plan.income - totalAssigned,
    overspentCount,
  }
}
