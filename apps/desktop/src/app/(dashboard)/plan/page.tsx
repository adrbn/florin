import { PlanPage } from '@florin/core/components/plan'
import { queries } from '@/db/client'
import {
  copyPreviousMonthBudgetsAction,
  listPlanCategoryTransactionsAction,
  setCategoryAssignedAction,
} from './actions'

export const dynamic = 'force-dynamic'

interface PageProps {
  searchParams: Promise<{ month?: string }>
}

function parseMonth(raw: string | undefined): { year: number; month: number } {
  if (raw && /^\d{4}-\d{2}$/.test(raw)) {
    const parts = raw.split('-').map(Number)
    const y = parts[0]!
    const m = parts[1]!
    if (m >= 1 && m <= 12) return { year: y, month: m }
  }
  const now = new Date()
  return { year: now.getUTCFullYear(), month: now.getUTCMonth() + 1 }
}

export default async function Plan({ searchParams }: PageProps) {
  const params = await searchParams
  const { year, month } = parseMonth(params.month)
  const plan = await queries.getMonthPlan(year, month)

  return (
    <PlanPage
      plan={plan}
      currency="EUR"
      onSetAssigned={setCategoryAssignedAction}
      onCopyPreviousMonth={copyPreviousMonthBudgetsAction}
      onListCategoryTransactions={listPlanCategoryTransactionsAction}
    />
  )
}
