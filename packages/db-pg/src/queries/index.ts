import { asc, eq } from 'drizzle-orm'
import type { FlorinQueries } from '@florin/core/types'
import type { PgDB } from '../client'
import {
  accounts,
  bankConnections,
  categories,
  categorizationRules,
  categoryGroups,
} from '../schema'
import {
  getNetWorth,
  getMonthBurn,
  getAvgMonthlyBurn,
  getPatrimonyTimeSeries,
  getMonthByCategory,
  getTopExpenses,
  countUncategorizedExpensesThisMonth,
  getDataSourceInfo,
  getLeftToSpendThisMonth,
  getDailySpend,
  getDailySpendByCategory,
  getSavingsRates,
  getSubscriptions,
} from './dashboard'
import {
  getMonthlyFlows,
  getCategoryBreakdown,
  getAgeOfMoney,
  getAgeOfMoneyHistory,
  getNetWorthSeries,
  getCategorySpendingSeries,
} from './reflect'
import { getMonthPlanQuery } from './plan'

export { getNetWorth } from './dashboard'
export { getLoanLiabilities } from './loan-liabilities'

/**
 * Build a FlorinQueries implementation backed by a PostgreSQL connection.
 * Each method delegates to the standalone query function, passing in the
 * shared `db` instance so the query layer stays free of global singletons.
 */
export function createPgQueries(db: PgDB): FlorinQueries {
  return {
    getNetWorth: () => getNetWorth(db),
    getMonthBurn: (opts) => getMonthBurn(db, opts),
    getAvgMonthlyBurn: (months) => getAvgMonthlyBurn(db, months),
    getPatrimonyTimeSeries: (months) => getPatrimonyTimeSeries(db, months),
    getMonthByCategory: () => getMonthByCategory(db),
    getTopExpenses: (n, days, categoryId) => getTopExpenses(db, n, days, categoryId),
    countUncategorizedExpensesThisMonth: () => countUncategorizedExpensesThisMonth(db),
    getDataSourceInfo: () => getDataSourceInfo(db),
    getMonthlyFlows: (months) => getMonthlyFlows(db, months),
    getCategoryBreakdown: (days) => getCategoryBreakdown(db, days),
    getAgeOfMoney: (days) => getAgeOfMoney(db, days),
    getAgeOfMoneyHistory: (months) => getAgeOfMoneyHistory(db, months),
    getNetWorthSeries: (months) => getNetWorthSeries(db, months),
    getCategorySpendingSeries: (months) => getCategorySpendingSeries(db, months),
    getMonthPlan: (year, month) => getMonthPlanQuery(db, year, month),
    getLeftToSpendThisMonth: () => getLeftToSpendThisMonth(db),
    getDailySpend: (days) => getDailySpend(db, days),
    getDailySpendByCategory: (days) => getDailySpendByCategory(db, days),
    getSavingsRates: () => getSavingsRates(db),
    getSubscriptions: () => getSubscriptions(db),

    // ---------- listing queries ----------

    listTransactions: async (options = {}) => {
      const { listTransactionsQuery } = await import('./transactions')
      return listTransactionsQuery(db, options)
    },
    countTransactions: async (options = {}) => {
      const { countTransactionsQuery } = await import('./transactions')
      return countTransactionsQuery(db, options)
    },
    countNeedsReview: async () => {
      const { countNeedsReviewQuery } = await import('./transactions')
      return countNeedsReviewQuery(db)
    },

    listAccounts: async (options = {}) => {
      const where = options.includeArchived ? undefined : eq(accounts.isArchived, false)
      const query = db
        .select()
        .from(accounts)
        .orderBy(asc(accounts.displayOrder), asc(accounts.name))
      const rows = where ? await query.where(where) : await query
      return rows
    },

    getAccountById: async (id) => {
      const row = await db.query.accounts.findFirst({
        where: eq(accounts.id, id),
        with: { bankConnection: true },
      })
      return row ?? null
    },

    listBankConnections: async () => {
      return db.select().from(bankConnections)
    },

    listCategoriesByGroup: async () => {
      return db.query.categoryGroups.findMany({
        orderBy: (g) => [asc(g.displayOrder), asc(g.name)],
        with: {
          categories: {
            orderBy: (c) => [asc(c.displayOrder), asc(c.name)],
          },
        },
      })
    },

    listCategoriesFlat: async () => {
      return db
        .select({
          id: categories.id,
          name: categories.name,
          emoji: categories.emoji,
          groupName: categoryGroups.name,
          linkedLoanAccountId: categories.linkedLoanAccountId,
        })
        .from(categories)
        .innerJoin(categoryGroups, eq(categories.groupId, categoryGroups.id))
        .orderBy(asc(categoryGroups.name), asc(categories.name))
    },

    listCategorizationRules: async () => {
      return db.select().from(categorizationRules)
    },
  }
}
