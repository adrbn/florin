import { TopExpensesList, type TopExpensesListProps } from './top-expenses-list'

/**
 * Presentational wrapper — the page passes pre-fetched initial data and
 * the fetchTopExpenses action so the client component can refresh.
 */
export type TopExpensesCardProps = TopExpensesListProps

export function TopExpensesCard(props: TopExpensesCardProps) {
  return <TopExpensesList {...props} />
}
