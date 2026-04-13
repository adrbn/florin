import {
  and,
  desc,
  eq,
  gte,
  inArray,
  isNull,
  lte,
  or,
  sql,
} from 'drizzle-orm'
import type { ListTransactionsOptions } from '@florin/core/types'
import type { SqliteDB } from '../client'
import { accounts, transactions } from '../schema'

/**
 * Build the WHERE clause for list/count transaction queries. Factored out so
 * both use the exact same predicate.
 */
function buildTransactionConditions(db: SqliteDB, options: ListTransactionsOptions) {
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
    // Include transactions on active accounts OR orphaned (account deleted)
    or(
      inArray(transactions.accountId, activeAccountIds),
      isNull(transactions.accountId),
    )!,
  ]
  if (accountId) conditions.push(eq(transactions.accountId, accountId))
  if (needsReviewOnly) conditions.push(eq(transactions.needsReview, true))
  if (startDate) conditions.push(gte(transactions.occurredAt, startDate))
  if (endDate) conditions.push(lte(transactions.occurredAt, endDate))
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
        sql`${transactions.normalizedPayee} LIKE ${needle} COLLATE NOCASE`,
        sql`${transactions.payee} LIKE ${needle} COLLATE NOCASE`,
      )!,
    )
  }
  if (categoryId === 'none') {
    conditions.push(isNull(transactions.categoryId))
  } else if (categoryId) {
    conditions.push(eq(transactions.categoryId, categoryId))
  }
  if (typeof minAmount === 'number' && Number.isFinite(minAmount)) {
    conditions.push(sql`${transactions.amount} >= ${minAmount}`)
  }
  if (typeof maxAmount === 'number' && Number.isFinite(maxAmount)) {
    conditions.push(sql`${transactions.amount} <= ${maxAmount}`)
  }
  return conditions
}

export async function countTransactionsQuery(
  db: SqliteDB,
  options: ListTransactionsOptions = {},
): Promise<number> {
  const conditions = buildTransactionConditions(db, options)
  const rows = await db
    .select({ count: sql<number>`COUNT(*)` })
    .from(transactions)
    .where(and(...conditions))
  return Number(rows[0]?.count ?? 0)
}

export async function listTransactionsQuery(
  db: SqliteDB,
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

export async function countNeedsReviewQuery(db: SqliteDB): Promise<number> {
  const rows = await db
    .select({ count: sql<number>`COUNT(*)` })
    .from(transactions)
    .innerJoin(accounts, eq(transactions.accountId, accounts.id))
    .where(
      and(
        isNull(transactions.deletedAt),
        eq(transactions.needsReview, true),
        eq(accounts.isArchived, false),
      ),
    )
  return Number(rows[0]?.count ?? 0)
}
