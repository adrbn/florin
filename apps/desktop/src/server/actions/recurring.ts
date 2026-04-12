'use server'

import { and, eq, isNull, lt, desc, sql } from 'drizzle-orm'
import { db } from '@/db/client'
import { transactions } from '@/db/schema'

export interface RecurringPattern {
  normalizedPayee: string
  payee: string
  avgAmount: number
  occurrences: number
  avgDaysBetween: number
  lastDate: string
  predictedNextDate: string
  categoryName: string | null
  categoryEmoji: string | null
}

/**
 * Detect recurring transactions by analyzing payee patterns.
 * A transaction is considered recurring if the same normalized payee appears
 * 3+ times with a roughly consistent interval (within 20% tolerance).
 */
export async function detectRecurringTransactions(): Promise<RecurringPattern[]> {
  // Get all non-deleted expense transactions grouped by normalized payee
  const rows = await db
    .select({
      normalizedPayee: transactions.normalizedPayee,
      payee: transactions.payee,
      amount: transactions.amount,
      occurredAt: transactions.occurredAt,
    })
    .from(transactions)
    .where(
      and(
        isNull(transactions.deletedAt),
        lt(transactions.amount, 0), // expenses only
      ),
    )
    .orderBy(transactions.normalizedPayee, desc(transactions.occurredAt))

  // Group by normalized payee
  const groups = new Map<string, { payee: string; amounts: number[]; dates: string[] }>()

  for (const row of rows) {
    const key = row.normalizedPayee || row.payee.toLowerCase().trim()
    if (!key) continue

    const existing = groups.get(key)
    if (existing) {
      existing.amounts.push(Number(row.amount))
      existing.dates.push(row.occurredAt)
    } else {
      groups.set(key, {
        payee: row.payee,
        amounts: [Number(row.amount)],
        dates: [row.occurredAt],
      })
    }
  }

  const patterns: RecurringPattern[] = []

  for (const [normalizedPayee, group] of groups) {
    // Need at least 3 occurrences
    if (group.amounts.length < 3) continue

    // Sort dates chronologically
    const dates = group.dates
      .map((d) => new Date(d))
      .sort((a, b) => a.getTime() - b.getTime())

    // Calculate intervals between consecutive transactions (in days)
    const intervals: number[] = []
    for (let i = 1; i < dates.length; i++) {
      const diff = (dates[i]!.getTime() - dates[i - 1]!.getTime()) / (1000 * 60 * 60 * 24)
      intervals.push(diff)
    }

    if (intervals.length === 0) continue

    const avgInterval = intervals.reduce((a, b) => a + b, 0) / intervals.length

    // Skip if interval is too short (< 7 days) or too long (> 100 days)
    if (avgInterval < 7 || avgInterval > 100) continue

    // Check consistency: at least 60% of intervals should be within 40% of average
    const consistentCount = intervals.filter(
      (i) => Math.abs(i - avgInterval) / avgInterval < 0.4,
    ).length
    if (consistentCount / intervals.length < 0.6) continue

    const avgAmount = group.amounts.reduce((a, b) => a + b, 0) / group.amounts.length
    const lastDate = dates[dates.length - 1]!
    const predictedNext = new Date(lastDate.getTime() + avgInterval * 24 * 60 * 60 * 1000)

    // Look up the category for the most recent transaction
    const recentTx = await db
      .select({
        categoryName: sql<string | null>`(SELECT c.name FROM categories c WHERE c.id = ${transactions.categoryId})`,
        categoryEmoji: sql<string | null>`(SELECT c.emoji FROM categories c WHERE c.id = ${transactions.categoryId})`,
      })
      .from(transactions)
      .where(
        and(
          isNull(transactions.deletedAt),
          eq(transactions.normalizedPayee, normalizedPayee),
        ),
      )
      .orderBy(desc(transactions.occurredAt))
      .limit(1)

    patterns.push({
      normalizedPayee,
      payee: group.payee,
      avgAmount,
      occurrences: group.amounts.length,
      avgDaysBetween: Math.round(avgInterval),
      lastDate: lastDate.toISOString().split('T')[0]!,
      predictedNextDate: predictedNext.toISOString().split('T')[0]!,
      categoryName: recentTx[0]?.categoryName ?? null,
      categoryEmoji: recentTx[0]?.categoryEmoji ?? null,
    })
  }

  // Sort by number of occurrences descending
  patterns.sort((a, b) => b.occurrences - a.occurrences)

  return patterns.slice(0, 20) // Limit to top 20
}
