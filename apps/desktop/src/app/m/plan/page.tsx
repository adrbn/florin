import { PlanScreen } from '@florin/core/components/v2/screens/plan'
import { queries } from '@/db/client'
import { setCategoryAssignedAction } from '../../(dashboard)/plan/actions'

export const dynamic = 'force-dynamic'

function parseMonth(raw: string | undefined): { year: number; month: number } {
  if (raw && /^\d{4}-\d{2}$/.test(raw)) {
    const [y, m] = raw.split('-').map(Number)
    if (y && m && m >= 1 && m <= 12) return { year: y, month: m }
  }
  const now = new Date()
  return { year: now.getUTCFullYear(), month: now.getUTCMonth() + 1 }
}

export default async function V2Plan({
  searchParams,
}: {
  searchParams: Promise<{ month?: string }>
}) {
  const { month: raw } = await searchParams
  const { year, month } = parseMonth(raw)
  const plan = await queries.getMonthPlan(year, month)
  return <PlanScreen plan={plan} onSetAssigned={setCategoryAssignedAction} />
}
