/**
 * Shared categorical palette for charts that need to distinguish many
 * series by hue alone (the category pie on the dashboard, the Reflect
 * breakdown bar chart). The earlier dashboard-only 5-colour variant pulled
 * from `--chart-1 … --chart-5` produced near-duplicate wedges whenever a
 * user had more than 5 categories — this ten-stop palette keeps them
 * visually distinct even in the long tail.
 *
 * Order matters: the first few are the "hero" hues (blue, emerald, amber,
 * red, purple) so small datasets still look intentional.
 */
export const CATEGORICAL_PALETTE = [
  '#3b82f6',
  '#10b981',
  '#f59e0b',
  '#ef4444',
  '#a855f7',
  '#0ea5e9',
  '#ec4899',
  '#22c55e',
  '#eab308',
  '#f97316',
] as const
