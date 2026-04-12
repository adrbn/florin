import { asc, eq } from 'drizzle-orm'
import { ApproveAllButton } from '@florin/core/components/review/approve-all-button'
import { ReviewTable } from '@florin/core/components/review/review-table'
import { Card, CardContent, CardHeader, CardTitle } from '@florin/core/components/ui/card'
import { db } from '@/db/client'
import { categories, categoryGroups } from '@/db/schema'
import { formatCurrencySigned } from '@florin/core/lib/format'
import {
  approveAllTransactions,
  approveTransaction,
  softDeleteTransaction,
  updateTransactionCategory,
  bulkApproveTransactions,
  bulkSoftDeleteTransactions,
  bulkUpdateTransactionCategory,
  listTransactions,
} from '@/server/actions/transactions'

const dateFormatter = new Intl.DateTimeFormat('fr-FR', {
  day: '2-digit',
  month: '2-digit',
  year: '2-digit',
})

export default async function ReviewPage() {
  const [pending, categoryList] = await Promise.all([
    listTransactions({ needsReviewOnly: true, limit: 500 }),
    db
      .select({
        id: categories.id,
        name: categories.name,
        emoji: categories.emoji,
        groupName: categoryGroups.name,
      })
      .from(categories)
      .innerJoin(categoryGroups, eq(categories.groupId, categoryGroups.id))
      .orderBy(asc(categoryGroups.name), asc(categories.name)),
  ])

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Review</h1>
          <p className="text-muted-foreground">
            New imports waiting for approval. Confirm payee + category before they count.
          </p>
        </div>
        {pending.length > 0 && (
          <ApproveAllButton
            count={pending.length}
            onApproveAllTransactions={approveAllTransactions}
          />
        )}
      </div>

      <Card>
        <CardHeader className="pb-2">
          <CardTitle className="text-sm">
            {pending.length === 0 ? 'Nothing waiting for review' : `${pending.length} pending`}
          </CardTitle>
        </CardHeader>
        <CardContent className="p-0">
          {pending.length === 0 ? (
            <p className="px-4 py-8 text-center text-sm text-muted-foreground">
              All caught up. Bank imports will appear here next time.
            </p>
          ) : (
            <ReviewTable
              rows={pending.map((t) => {
                const amount = Number(t.amount)
                return {
                  transactionId: t.id,
                  date: dateFormatter.format(t.occurredAt),
                  payee: t.payee || '(no payee)',
                  accountName: t.account?.name ?? '—',
                  amount,
                  amountFormatted: formatCurrencySigned(amount),
                  currentCategoryId: t.category?.id ?? null,
                  currentCategoryName: t.category?.name ?? null,
                  currentCategoryEmoji: t.category?.emoji ?? null,
                }
              })}
              categoryOptions={categoryList}
              actions={{
                onApproveTransaction: approveTransaction,
                onSoftDeleteTransaction: softDeleteTransaction,
                onUpdateTransactionCategory: updateTransactionCategory,
                onBulkApproveTransactions: bulkApproveTransactions,
                onBulkSoftDeleteTransactions: bulkSoftDeleteTransactions,
                onBulkUpdateTransactionCategory: bulkUpdateTransactionCategory,
              }}
            />
          )}
        </CardContent>
      </Card>
    </div>
  )
}
