## What this changes

<!-- One or two sentences: the problem, and what this does about it. -->

## How it was checked

<!-- Tests added or run, and for anything computed: what the figure was checked against. -->

## Checklist

- [ ] A schema or query change lands in both `db-pg` and `db-sqlite` (and the iPhone ledger if it has the table)
- [ ] A computed figure is pinned by a test against something real
- [ ] New strings exist in every language the surface ships
- [ ] `pnpm --filter @florin/web exec vitest run` passes
