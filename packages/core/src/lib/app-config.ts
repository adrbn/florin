/**
 * User-tunable app defaults.
 *
 * Florin ships France/EUR-first defaults (a 100 k€ goal, a 7 %/yr assumed
 * return, the 150 k€ PEA ceiling). Those are only sensible starting points —
 * a different user has a different target, a different expected return, and no
 * PEA at all. This module centralises the defaults and the resolver so each app
 * can override them from its own config channel (the web app from env vars, the
 * desktop app from its SQLite `settings` table) without the values being
 * hardcoded at call sites.
 */

export interface AppConfig {
  /** Long-term wealth target shown on the goal card, in the app currency. */
  goalTarget: number
  /** Assumed net annual return used to project the goal, as a percent (7 = 7%). */
  goalReturnPct: number
  /**
   * Contribution ceiling for a tax-wrapped account (France's PEA = 150 000 €).
   * Set to 0 to disable the "versé / plafond" gauge entirely for users whose
   * account has no such cap.
   */
  peaCeiling: number
  /**
   * Planned monthly investment (the DCA the user intends to keep up), in the
   * app currency. Feeds the goal projection directly — a stated intention, not
   * a guess from history. 0 means "not set": the goal falls back to detecting
   * the rate from recent contributions.
   */
  plannedMonthlyInvestment: number
}

export const DEFAULT_APP_CONFIG: AppConfig = {
  goalTarget: 100_000,
  goalReturnPct: 7,
  peaCeiling: 150_000,
  plannedMonthlyInvestment: 0,
}

/** Parse a possibly-undefined string/number override, falling back to `fallback`. */
export function resolveNumber(
  raw: string | number | null | undefined,
  fallback: number,
): number {
  if (raw === null || raw === undefined || raw === '') return fallback
  const n = typeof raw === 'number' ? raw : Number(raw)
  return Number.isFinite(n) && n >= 0 ? n : fallback
}

/**
 * Merge partial overrides (any subset, any source) over {@link DEFAULT_APP_CONFIG}.
 * Non-numeric / negative / missing values fall back to the default per field.
 */
export function resolveAppConfig(
  overrides: Partial<Record<keyof AppConfig, string | number | null | undefined>> = {},
): AppConfig {
  return {
    goalTarget: resolveNumber(overrides.goalTarget, DEFAULT_APP_CONFIG.goalTarget),
    goalReturnPct: resolveNumber(overrides.goalReturnPct, DEFAULT_APP_CONFIG.goalReturnPct),
    peaCeiling: resolveNumber(overrides.peaCeiling, DEFAULT_APP_CONFIG.peaCeiling),
    plannedMonthlyInvestment: resolveNumber(
      overrides.plannedMonthlyInvestment,
      DEFAULT_APP_CONFIG.plannedMonthlyInvestment,
    ),
  }
}
