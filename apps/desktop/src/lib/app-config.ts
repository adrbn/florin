import { inArray } from 'drizzle-orm'
import { resolveAppConfig, type AppConfig } from '@florin/core/lib/app-config'
import { db } from '@/db/client'
import { settings } from '@/db/schema'

/** Settings-table keys backing the tunable app defaults. */
export const APP_CONFIG_KEYS = [
  'goal_target',
  'goal_return_pct',
  'pea_ceiling',
  'planned_monthly_investment',
] as const

/**
 * Desktop resolves the tunable defaults from the SQLite `settings` table (the
 * same key-value store that holds locale / currency / Enable Banking config),
 * editable from the Settings page. Missing / invalid rows fall back to the
 * France/EUR-first defaults.
 */
export async function getAppConfig(): Promise<AppConfig> {
  try {
    const rows = await db
      .select()
      .from(settings)
      .where(inArray(settings.key, APP_CONFIG_KEYS as unknown as string[]))
    const map = new Map(rows.map((r) => [r.key, r.value]))
    return resolveAppConfig({
      goalTarget: map.get('goal_target'),
      goalReturnPct: map.get('goal_return_pct'),
      peaCeiling: map.get('pea_ceiling'),
      plannedMonthlyInvestment: map.get('planned_monthly_investment'),
    })
  } catch {
    return resolveAppConfig()
  }
}
