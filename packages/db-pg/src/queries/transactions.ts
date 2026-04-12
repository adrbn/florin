import {
  and,
  desc,
  eq,
  gte,
  ilike,
  inArray,
  isNull,
  lte,
  or,
  sql,
} from 'drizzle-orm'
import type { ListTransactionsOptions } from '@florin/core/types'
import type { PgDB } from '../client'
import { accounts, transactions } from '../schema'

/**
 * Build the WHERE clause for list/count transaction queries. Factored out so
 * both use the exact same predicate.
 */
function buildTransactionConditions(db: PgDB, options: ListTransactionsOptions) {
  const {
    accountId,
    needsReviewOnly = false,
    startDate,
    endDate,
    direction = 'all',
    excludeTransfers = false,
    payeeSearch,
    categoryId,
    minAmount,
    maxAmount,
  } = options
  const activeAccountIds = db
    .select({ id: accounts.id })
    .from(accounts)
    .where(eq(accounts.isArchived, false))
  const conditions = [
    isNull(transactions.deletedAt),
    inArray(transactions.accountId, activeAccountIds),
  ]
  if (accountId) conditions.push(eq(transactions.accountId, accountId))
  if (needsReviewOnly) conditions.push(eq(transactions.needsReview, true))
  if (startDate) conditions.push(gte(transactions.occurredAt, new Date(startDate)))
  if (endDate) conditions.push(lte(transactions.occurredAt, new Date(endDate)))
  if (direction === 'expense') {
    conditions.push(sql`${transactions.amount} < 0`)
  } else if (direction === 'income') {
    conditions.push(sql`${transactions.amount} > 0`)
  }
  if (excludeTransfers) {
    conditions.push(isNull(transactions.transferPairId))
  }
  if (payeeSearch && payeeSearch.trim().length > 0) {
    const needle = `%${payeeSearch.trim()}%`
    conditions.push(
      or(
        ilike(transactions.normalizedPayee, needle),
        ilike(transactions.payee, needle),
      )!,
    )
  }
  if (categoryId === 'none') {
    conditions.push(isNull(transactions.categoryId))
  } else if (categoryId) {
    conditions.push(eq(transactions.categoryId, categoryId))
  }
  if (typeof minAmount === 'number' && Number.isFinite(minAmount)) {
    conditions.push(sql`${transactions.amount} >= ${minAmount.toFixed(2)}`)
  }
  if (typeof maxAmount === 'number' && Number.isFinite(maxAmount)) {
    conditions.push(sql`${transactions.amount} <= ${maxAmount.toFixed(2)}`)
  }
  return conditions
}

export async function countTransactionsQuery(
  db: PgDB,
  options: ListTransactionsOptions = {},
): Promise<number> {
  const conditions = buildTransactionConditions(db, options)
  const rows = await db
    .select({ count: sql<string>`COUNT(*)` })
    .from(transactions)
    .where(and(...conditions))
  return Number(rows[0]?.count ?? '0')
}

export async function listTransactionsQuery(
  db: PgDB,
  options: ListTransactionsOptions = {},
) {
  const { limit = 100, offset = 0 } = options
  const conditions = buildTransactionConditions(db, options)
  return db.query.transactions.findMany({
    where: and(...conditions),
    orderBy: [desc(transactions.occurredAt), desc(transactions.createdAt)],
    limit,
    offset,
    with: {
      account: true,
      category: true,
    },
  })
}

export async function countNeedsReviewQuery(db: PgDB): Promise<number> {
  const rows = await db
    .select({ count: sql<string>`COUNT(*)` })
    .from(transactions)
    .innerJoin(accounts, eq(transactions.accountId, accounts.id))
    .where(
      and(
        isNull(transactions.deletedAt),
        eq(transactions.needsReview, true),
        eq(accounts.isArchived, false),
      ),
    )
  return Number(rows[0]?.count ?? '0')
}
