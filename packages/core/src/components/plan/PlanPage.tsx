'use client'

import { useEffect, useState, useTransition } from 'react'
import { useRouter, useSearchParams } from 'next/navigation'
import { toast } from 'sonner'
import type {
  ActionResult,
  ListPlanCategoryTransactions,
  MonthPlan,
  SetCategoryAssignedInput,
} from '@florin/core/types'
import { MonthPicker } from './MonthPicker'
import { PlanGroup } from './PlanGroup'
import { PlanCategoryTransactionsModal } from './PlanCategoryTransactionsModal'

interface PlanPageProps {
  plan: MonthPlan
  currency: string
  onSetAssigned: (input: SetCategoryAssignedInput) => Promise<ActionResult>
  onListCategoryTransactions: ListPlanCategoryTransactions
}

type OpenCategory = { id: string; name: string; emoji: string | null } | null

export function PlanPage({ plan, currency, onSetAssigned, onListCategoryTransactions }: PlanPageProps) {
  const router = useRouter()
  const searchParams = useSearchParams()
  const [, startTransition] = useTransition()
  const [optimistic, setOptimistic] = useState<MonthPlan>(plan)
  const [openCategory, setOpenCategory] = useState<OpenCategory>(null)

  // Reset optimistic state whenever the server plan changes (month nav or post-save refresh).
  useEffect(() => {
    setOptimistic(plan)
  }, [plan])

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

  function handleShowTransactions(categoryId: string) {
    for (const g of optimistic.groups) {
      const c = g.categories.find((c) => c.id === categoryId)
      if (c) {
        setOpenCategory({ id: c.id, name: c.name, emoji: c.emoji })
        return
      }
    }
  }

  return (
    <div className="flex flex-col h-full min-h-0">
      <MonthPicker year={optimistic.year} month={optimistic.month} onChange={navigate} />
      {optimistic.overspentCount > 0 ? (
        <div className="px-4 py-2 border-b border-border">
          <span className="inline-flex items-center rounded-full bg-red-500/15 text-red-500 border border-red-500/30 px-2 py-0.5 text-xs font-medium">
            {optimistic.overspentCount} overspent
          </span>
        </div>
      ) : null}
      <div className="flex-1 overflow-y-auto">
        {optimistic.groups.map((g) => (
          <PlanGroup
            key={g.id}
            group={g}
            currency={currency}
            onAssignedChange={handleAssignedChange}
            onShowTransactions={handleShowTransactions}
          />
        ))}
      </div>
      <PlanCategoryTransactionsModal
        open={openCategory !== null}
        onOpenChange={(v) => {
          if (!v) setOpenCategory(null)
        }}
        category={openCategory}
        year={optimistic.year}
        month={optimistic.month}
        onListTransactions={onListCategoryTransactions}
      />
    </div>
  )
}

function recomputeWithAssigned(plan: MonthPlan, categoryId: string, newAmount: number): MonthPlan {
  const r = (x: number) => Math.round(x * 100) / 100
  let totalAssigned = 0
  let overspentCount = 0
  const groups = plan.groups.map((g) => {
    let gAssigned = 0
    let gAvailable = 0
    let gOverspent = 0
    const categories = g.categories.map((c) => {
      const assigned = r(c.id === categoryId ? newAmount : c.assigned)
      const available = r(assigned - c.spent)
      gAssigned += assigned
      gAvailable += available
      if (available < 0) gOverspent += 1
      return { ...c, assigned, available }
    })
    totalAssigned += gAssigned
    overspentCount += gOverspent
    return { ...g, categories, assigned: r(gAssigned), available: r(gAvailable), overspentCount: gOverspent }
  })
  const roundedTotal = r(totalAssigned)
  return {
    ...plan,
    groups,
    totalAssigned: roundedTotal,
    readyToAssign: r(plan.income - roundedTotal),
    overspentCount,
  }
}
