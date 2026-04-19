# Plan Tab — Design Spec

## Overview

A new "Plan" surface in Florin that lets the user assign a maximum spend amount per category per month, then see live `Available = Assigned − Spent` as transactions land. Modeled on YNAB's envelope budgeting, with a critical simplification: **no month-to-month rollover** (unspent disappears at month end, each month is independent). Budgeting happens at the category level only; category-group totals are derived sums. Future months are fully editable (you can plan May in April). Ships on both desktop (SQLite) and web (PostgreSQL).

## Goals

- Replace ad-hoc "am I overspending?" intuition with a deterministic per-category cap.
- Keep the mental model trivially simple — one number per category per month, no rollover bookkeeping.
- Make "overspent" and "assigned too much" impossible to miss.
- Allow pre-assignment of future months so recurring bills can be planned ahead.

## Non-Goals (v1)

- No rollover of Available into next month.
- No "cover overspending" inline UI (user just edits the numbers manually).
- No YNAB-style "Targets" / savings goals.
- No multi-currency budget lines — all budgets in the user's `baseCurrency`.
- No group-level assigned amounts — group totals are pure sums of their categories.
- No budget templates / copy-from-previous-month on the first release (considered for v1.1, see Open Questions).

## Terminology

| Term | Meaning |
|---|---|
| Assigned | Amount the user has budgeted for this category this month. |
| Spent | Sum of absolute expense amounts in this category this month. Transfers excluded. |
| Available | `Assigned − Spent`. Green if ≥ 0, red if < 0 (overspent). |
| Income (month) | Sum of transactions dated in the month whose category belongs to an `income`-kind group. Transfers excluded. |
| Total Assigned | Sum of `Assigned` across all categories for that month. |
| Ready to Assign | `Income − Total Assigned`. If negative, UI renders as "Assigned Too Much" (red). |
| Overspent Count | Number of categories with `Available < 0` this month. |

## Data Model

One new table in both `packages/db-sqlite/src/schema.ts` and `packages/db-pg/src/schema.ts`:

```ts
// sqlite
export const monthlyBudgets = sqliteTable(
  'monthly_budgets',
  {
    id: text('id').primaryKey().$defaultFn(() => randomUUID()),
    year: integer('year').notNull(),        // e.g. 2026
    month: integer('month').notNull(),      // 1–12
    categoryId: text('category_id')
      .notNull()
      .references(() => categories.id, { onDelete: 'cascade' }),
    assigned: real('assigned').notNull().default(0),
    note: text('note'),
    createdAt: text('created_at').notNull().default(sql`(datetime('now'))`),
    updatedAt: text('updated_at').notNull().default(sql`(datetime('now'))`),
  },
  (t) => [
    uniqueIndex('monthly_budgets_ymc_unique').on(t.year, t.month, t.categoryId),
    index('monthly_budgets_ym_idx').on(t.year, t.month),
  ],
)
```

Same shape for `db-pg` using `pgTable` / `integer` / `numeric(12, 2)` for `assigned`, `timestamp` for the timestamps.

**Why (year, month) as two integer columns instead of a single text "2026-04"?**
- Cheap range queries ("next 6 months") stay trivial.
- Month-picker UI composes month without string parsing.
- Index ordering is natural (year DESC, month DESC).

**Why no `userId`?**
Florin is single-user today (no other table has userId either). If multi-user lands, this table gets the same treatment as `categories` and `transactions` in one migration.

**Why store `assigned` instead of computing from a separate "assignments" log table?**
The log-based design (YNAB's actual internal model) unlocks audit trails and undo, but those are non-goals. One row per (year, month, category) is dramatically simpler and covers every v1 use case. If we later want audit, we add a `monthly_budget_events` table without rewriting this one.

## Computed Values (per month view)

All computed at query time — nothing cached, nothing denormalized. Single round-trip to build a full month view:

```sql
-- Pseudo-SQL; real impl uses Drizzle.
-- Parameters: :year, :month, :startOfMonth, :startOfNextMonth

-- 1. Budgets for the month, with category + group info:
SELECT mb.category_id, mb.assigned, c.name, c.emoji, cg.id AS group_id, cg.name AS group_name, cg.kind
  FROM categories c
  JOIN category_groups cg ON cg.id = c.group_id
  LEFT JOIN monthly_budgets mb
    ON mb.category_id = c.id AND mb.year = :year AND mb.month = :month
  WHERE c.is_archived = 0
  ORDER BY cg.display_order, c.display_order;

-- 2. Spent per category (expense transactions in the month, transfers excluded):
SELECT t.category_id, SUM(ABS(t.amount)) AS spent
  FROM transactions t
  JOIN categories c ON c.id = t.category_id
  JOIN category_groups cg ON cg.id = c.group_id
  WHERE t.occurred_at >= :startOfMonth
    AND t.occurred_at < :startOfNextMonth
    AND t.deleted_at IS NULL
    AND t.transfer_pair_id IS NULL
    AND cg.kind = 'expense'
  GROUP BY t.category_id;

-- 3. Income for the month:
SELECT COALESCE(SUM(t.amount), 0) AS income
  FROM transactions t
  JOIN categories c ON c.id = t.category_id
  JOIN category_groups cg ON cg.id = c.group_id
  WHERE t.occurred_at >= :startOfMonth
    AND t.occurred_at < :startOfNextMonth
    AND t.deleted_at IS NULL
    AND t.transfer_pair_id IS NULL
    AND cg.kind = 'income';
```

The server then composes `Available = assigned − spent` per category, `Ready to Assign = income − SUM(assigned)`, and `Overspent Count = COUNT(available < 0)`.

**Indexes we rely on** (already exist, no new index work for transactions):
- `transactions_category_date_idx` on `(category_id, occurred_at)` — used by Spent query.
- `transactions_not_deleted_idx` — soft-delete filter.
- New: `monthly_budgets_ymc_unique` on `(year, month, categoryId)` — primary lookup.

## Architecture — Layers

**Schema & migrations** (`packages/db-sqlite`, `packages/db-pg`)
- Add `monthlyBudgets` table + relation to `categories`.
- One new Drizzle migration per package.

**Queries + Actions** (`packages/db-sqlite/src/queries`, `packages/db-sqlite/src/actions`, and PG equivalents)
- `queries/plan.ts`:
  - `getMonthPlan(year, month): MonthPlan` — single call returning groups → categories with assigned/spent/available + month totals.
- `actions/plan.ts`:
  - `setCategoryAssigned(year, month, categoryId, amount, note?)` — upsert into `monthly_budgets`.
  - `clearCategoryAssigned(year, month, categoryId)` — delete the row.

Both are registered in the existing `FlorinQueries` / `FlorinActions` interfaces in `packages/core/types`. Each app binds its own implementation (desktop via IPC → SQLite, web via server actions → PG).

**Shared UI** (`packages/core/src/components/plan/`)
- `PlanPage.tsx` — top-level. Takes `monthPlan`, `onSetAssigned`, `onChangeMonth` as props (no server imports).
- `PlanBanner.tsx` — the "Ready to Assign" / "Assigned Too Much" / overspent count banner.
- `PlanGroup.tsx` — collapsible group header with aggregated Assigned / Available.
- `PlanCategoryRow.tsx` — emoji + name, editable Assigned input, Available pill.
- `MonthPicker.tsx` — reuses existing month-nav pattern if one exists, otherwise new.

**Routes**
- `apps/web/src/app/(dashboard)/plan/page.tsx` — server-loads current month, binds web actions.
- `apps/desktop/src/app/(dashboard)/plan/page.tsx` — same, binds desktop IPC actions.
- Both take an optional `?month=YYYY-MM` search param; default = current month in user's locale.

**Navigation**
- Add "Plan" entry to the dashboard sidebar/navbar (exact placement follows the existing layout pattern — likely between "Review" and "Accounts"). Icon: calendar or envelope-style.

## UX Flow

**Entering the Plan tab (current month, first time):**
1. Page loads `MonthPlan` for `getCurrentMonth()`.
2. No `monthly_budgets` rows exist yet → every category shows `Assigned = 0€`, `Available = 0€ − spent`.
3. If there's already Spent in any expense category and `assigned=0`, that row renders as overspent (red pill, negative number). This is correct behavior — the user literally has unbudgeted spending.
4. Banner shows `Ready to Assign = income − 0 = full income amount` (or 0€ if no income booked yet).

**Assigning a budget:**
1. User taps the "Assigned" cell on a category row → it becomes an inline number input.
2. On blur / Enter, fire `setCategoryAssigned(year, month, categoryId, amount)` optimistically.
3. Row's Available updates immediately; banner re-computes `Ready to Assign`.
4. On server error, revert the optimistic update and toast the error.

**Editing a future month:**
1. User taps the month-picker header → forward arrow → `/plan?month=2026-05`.
2. Page re-queries. May's spent is 0 (no transactions yet), May's income is 0 (no income booked yet), Ready to Assign starts at 0€.
3. User can still assign — banner goes red ("Assigned Too Much") immediately. That's expected; the user is planning ahead against unrealized income.

**Overspent:**
- Any category where `Available < 0` renders its pill in red.
- Group row aggregates: if any child is overspent, the group header shows the normal "Assigned X€ / Available Y€" plus a small red badge with the count of overspent children in that group.
- Banner top-right shows "N Overspent categories" as an inline chip (no "Cover" action in v1).

**Assigned Too Much:**
- When `Total Assigned > Income`, banner turns red with `−X€ Assigned Too Much` (matching YNAB screenshot). Clicking it scrolls to the largest Assigned category as a hint (nice-to-have; skip if time-boxed).

## Edge Cases & Rules

| Case | Behavior |
|---|---|
| Transaction with `category_id = NULL` | Not counted in any category's Spent. Not counted in Income. User must categorize it to affect the plan. |
| Transaction in an archived category | Spent still tallied for that category if the category is still visible. If archived, category is hidden from grid entirely — Spent is silently dropped for this view. *(If we want to surface this, we'd add a "Hidden categories with spending this month" footer. Flag for v1.1.)* |
| Transfer transactions (`transfer_pair_id NOT NULL`) | Excluded from both Income and Spent. |
| Soft-deleted transactions (`deleted_at NOT NULL`) | Excluded from all computations. |
| Pending transactions (`is_pending = 1`) | **Included** in Spent — the envelope has already been "committed." (Rationale: pending charges are money gone from the user's perspective.) |
| `assigned = 0` with no `monthly_budgets` row | Treated identically to explicit `assigned = 0`. Row renders normally. |
| Negative `assigned` | Disallowed in v1. Server validates `amount >= 0`. |
| User deletes a category with budgets on it | Cascade deletes `monthly_budgets` rows (FK `onDelete: 'cascade'`). |
| Multi-currency transactions | Summed in raw amount into EUR (user's `baseCurrency`) without conversion. v1 limitation — documented in Open Questions. |

## Testing Strategy

**Unit tests** (`packages/core/src/components/plan/__tests__/`)
- `PlanCategoryRow` renders overspent state correctly (red pill, negative sign).
- `PlanBanner` switches modes: Ready to Assign (green) / Assigned Too Much (red) / empty-state (neutral).
- Month-picker navigation preserves query params.

**DB / query tests** (per-package, under `packages/db-sqlite/src/queries/__tests__/plan.test.ts` and PG equivalent)
- Seed: 3 categories across 2 groups, 10 transactions spanning 2 months, 1 transfer, 1 soft-deleted.
- `getMonthPlan` returns correct spent per category, correct income, correct Ready to Assign.
- Transfer is excluded.
- Soft-deleted transaction is excluded.
- Setting a budget then re-querying shows it.
- Upserting the same (year, month, categoryId) overwrites.
- Archived category is excluded from the grid.

**Integration / E2E** (Playwright, `apps/web/e2e/plan.spec.ts`)
- Full flow: create categories → record a few transactions → navigate to /plan → assign budgets → verify Available updates → overspend a category → verify red pill → navigate to next month → verify empty state.

**Target coverage**: 80%+ on `packages/core/src/components/plan/**` and the plan queries/actions in each db package.

## Migrations

- `packages/db-sqlite/migrations/NNNN_monthly_budgets.sql`: `CREATE TABLE monthly_budgets …` + indexes.
- `packages/db-pg/migrations/NNNN_monthly_budgets.sql`: same shape, PG types.
- No data backfill required — the table starts empty. First existing user loads the /plan page and sees 0€ everywhere, which is correct.

## Risks

| Risk | Mitigation |
|---|---|
| User expects rollover to "just work" and is confused when April's savings don't carry to May. | Onboarding tooltip on first Plan visit: "Florin resets every month — unspent money doesn't roll over. Assign fresh each month." |
| "Assigned Too Much" fires aggressively in early months when income hasn't landed yet. | Copy explicitly: "Income so far this month: X€. You can assign ahead of expected income, but the banner will stay red until money arrives." |
| Users with many categories (50+) on slow hardware see janky edits. | Debounce the Assigned input by 250ms; rely on optimistic UI so perceived latency is 0. |
| Schema drift between `db-sqlite` and `db-pg` (one package updated, the other forgotten). | Both migrations land in the same PR; CI test suite for each package runs the migration + a smoke `getMonthPlan` query. |

## Open Questions (tracked, not blocking v1)

1. **Copy-forward budgets**: should the first visit to an un-budgeted month pre-fill from the previous month? Intended v1.1. Default v1 = no copy, user starts each month fresh.
2. **Hidden-but-spent surface**: if an archived category has current-month spending, should we warn? Deferred.
3. **Multi-currency**: budgets are in `baseCurrency`; transactions in other currencies are summed at raw amount today (existing behavior elsewhere in Florin). Proper FX conversion is out of scope.
4. **"Cover overspending"**: YNAB's inline "cover with …" action. Deferred — user can edit numbers manually in v1.
5. **Group-level budgets**: explicitly rejected for v1. If the user ever wants a "max total for Wants", we'd add it as an optional column on `category_groups` and update Ready to Assign math. Not now.

## Success Criteria

- User can open `/plan`, assign budgets to every visible category in under 2 minutes.
- Recording a categorized transaction on `/transactions` updates `/plan`'s Available for that category on next visit, with no manual refresh beyond Next.js revalidation.
- The "Assigned Too Much" banner appears the moment total assigned exceeds month income, and disappears when the user reduces an assignment or more income lands.
- Both desktop and web ship the feature in the same release; schema migrations run cleanly on existing databases without user intervention.
