import { describe, expect, it } from 'vitest'
import {
  computeCategoryMovers,
  computeMonthForecast,
  computeRecurringSplit,
  computeSpendingAnomalies,
} from '@florin/core/lib/reflect/insights'
import type {
  CategorySpendingSeries,
  DailyCategorySpend,
  LeftToSpend,
  SubscriptionMatch,
} from '@florin/core/types'

describe('computeCategoryMovers', () => {
  const series: CategorySpendingSeries = {
    // last bucket (2026-06) is the in-progress month and must be ignored
    months: ['2026-04', '2026-05', '2026-06'],
    categories: [
      { categoryId: 'a', categoryName: 'Restaurants', emoji: '🍽️', monthly: [100, 250, 30], total: 380 },
      { categoryId: 'b', categoryName: 'Rent', emoji: '🏠', monthly: [800, 800, 800], total: 2400 },
      { categoryId: 'c', categoryName: 'Transport', emoji: '🚆', monthly: [60, 20, 5], total: 85 },
    ],
  }

  it('compares the two most recent COMPLETE months (ignores the in-progress one)', () => {
    const { currentMonth, previousMonth, movers } = computeCategoryMovers(series)
    expect(currentMonth).toBe('2026-05')
    expect(previousMonth).toBe('2026-04')
    // Restaurants +150 is the biggest mover; Rent (flat) is filtered out
    expect(movers[0]?.categoryName).toBe('Restaurants')
    expect(movers[0]?.delta).toBe(150)
    expect(movers[0]?.pct).toBe(150)
    expect(movers.some((m) => m.categoryName === 'Rent')).toBe(false)
  })

  it('ranks by absolute delta, surfacing drops too', () => {
    const { movers } = computeCategoryMovers(series)
    const transport = movers.find((m) => m.categoryName === 'Transport')
    expect(transport?.delta).toBe(-40)
  })

  it('returns nothing when there is not enough history', () => {
    const short: CategorySpendingSeries = { months: ['2026-06'], categories: [] }
    expect(computeCategoryMovers(short).movers).toEqual([])
  })
})

describe('computeMonthForecast', () => {
  const base: LeftToSpend = {
    salaryCategoryId: 'sal',
    salaryCategoryName: 'Salary',
    monthIncome: 3000,
    monthSpent: 1000,
    monthSpentFixed: 0,
    leftToSpend: 2000,
    dailyAvgSpent: 100,
    dailyBudgetRemaining: 100,
    daysElapsed: 10,
    daysRemaining: 20,
  }

  it('projects spend at the current pace and the resulting margin', () => {
    const f = computeMonthForecast(base)
    expect(f.projectedSpend).toBe(1000 + 100 * 20) // 3000
    expect(f.projectedMargin).toBe(0) // 3000 income − 3000 spend
    expect(f.onTrack).toBe(true)
  })

  it('flags an overspend pace as off-track', () => {
    // The forecast extrapolates VARIABLE spend (monthSpent − monthSpentFixed)
    // over the elapsed days, not raw dailyAvgSpent — so drive the overspend via
    // a higher monthSpent. 1500 over 10 days → 150/day → +150×20 remaining.
    const f = computeMonthForecast({ ...base, monthSpent: 1500 })
    expect(f.projectedSpend).toBe(1500 + 150 * 20) // 4500
    expect(f.projectedMargin).toBe(3000 - 4500) // −1500
    expect(f.onTrack).toBe(false)
  })

  it('returns null margin when no income is detected', () => {
    const f = computeMonthForecast({ ...base, monthIncome: 0 })
    expect(f.projectedMargin).toBeNull()
    expect(f.onTrack).toBeNull()
  })
})

describe('computeRecurringSplit', () => {
  const subs: SubscriptionMatch[] = [
    { payee: 'Netflix', amount: -15, cadenceDays: 30, samples: 4, lastSeen: '2026-06-01', annualCost: 182, categoryName: null },
    { payee: 'Gym', amount: -10, cadenceDays: 7, samples: 8, lastSeen: '2026-06-10', annualCost: 521, categoryName: null },
  ]

  it('normalises cadences to a monthly committed figure', () => {
    const r = computeRecurringSplit(subs, 1000)
    // Netflix 15 * 30.4368/30 + Gym 10 * 30.4368/7 ≈ 15.22 + 43.48 = 58.70
    expect(r.committedMonthly).toBeCloseTo(58.7, 1)
    expect(r.discretionaryMonthly).toBeCloseTo(941.3, 1)
    expect(r.subscriptionCount).toBe(2)
    expect(r.committedPct).toBeCloseTo(5.87, 1)
  })

  it('clamps committed pct to 100 and discretionary to 0', () => {
    const r = computeRecurringSplit(subs, 10)
    expect(r.committedPct).toBe(100)
    expect(r.discretionaryMonthly).toBe(0)
  })
})

describe('computeSpendingAnomalies', () => {
  const rows: DailyCategorySpend[] = [
    { date: '2026-06-01', categoryId: 'f', categoryName: 'Food', groupName: null, amount: 20 },
    { date: '2026-06-02', categoryId: 'f', categoryName: 'Food', groupName: null, amount: 20 },
    { date: '2026-06-03', categoryId: 'f', categoryName: 'Food', groupName: null, amount: 20 },
    // a clearly unusual day, dominated by Travel
    { date: '2026-06-10', categoryId: 't', categoryName: 'Travel', groupName: null, amount: 400 },
    { date: '2026-06-10', categoryId: 'f', categoryName: 'Food', groupName: null, amount: 30 },
  ]

  it('flags the unusual day with its dominant category', () => {
    const { anomalies, typicalDay } = computeSpendingAnomalies(rows)
    expect(typicalDay).toBe(20)
    expect(anomalies).toHaveLength(1)
    expect(anomalies[0]?.date).toBe('2026-06-10')
    expect(anomalies[0]?.amount).toBe(430)
    expect(anomalies[0]?.topCategoryName).toBe('Travel')
    expect(anomalies[0]?.multipleOfTypical).toBeCloseTo(21.5, 1)
  })

  it('returns nothing when every day is normal', () => {
    const flat: DailyCategorySpend[] = [
      { date: '2026-06-01', categoryId: 'f', categoryName: 'Food', groupName: null, amount: 20 },
      { date: '2026-06-02', categoryId: 'f', categoryName: 'Food', groupName: null, amount: 22 },
    ]
    expect(computeSpendingAnomalies(flat).anomalies).toEqual([])
  })
})
