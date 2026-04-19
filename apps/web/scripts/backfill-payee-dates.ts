#!/usr/bin/env tsx
/**
 * One-shot backfill: for every bank-synced transaction whose payee line
 * embeds a `DD.MM.YY` (or `/`, `-`) date — a common pattern with French
 * bank card purchases like `ACHAT CB BAR 14.04.26 EUR 7,00 ...` — pull
 * that date out and overwrite `occurred_at` with it. This corrects the
 * next-business-day posting drift that corrupts cross-month and
 * weekend-boundary views.
 *
 * Safety:
 *   - Only touches rows where `source IS NOT NULL` (never manual entries).
 *   - Only applies the extracted date when it's within ±14 days of the
 *     currently-stored date (guards against false positives).
 *   - Dry-run by default; pass `--apply` to actually write.
 *
 * Usage (from repo root):
 *   node --env-file=.env --import tsx \
 *     apps/web/scripts/backfill-payee-dates.ts [--apply]
 *
 * On asgard (container):
 *   pct exec 100 -- docker compose exec web \
 *     node --import tsx scripts/backfill-payee-dates.ts --apply
 */

import { eq, isNotNull, sql } from 'drizzle-orm'
import { db } from '../src/db/client'
import { transactions } from '../src/db/schema'
import { extractTrueDateFromText } from '@florin/core/lib/transactions'

interface BackfillStats {
  scanned: number
  candidates: number
  updated: number
  skippedNoMatch: number
  skippedSameDay: number
}

async function main(): Promise<void> {
  const apply = process.argv.includes('--apply')
  const stats: BackfillStats = {
    scanned: 0,
    candidates: 0,
    updated: 0,
    skippedNoMatch: 0,
    skippedSameDay: 0,
  }

  console.log(`[backfill] mode=${apply ? 'APPLY' : 'DRY-RUN'}`)

  const rows = await db
    .select({
      id: transactions.id,
      payee: transactions.payee,
      occurredAt: transactions.occurredAt,
    })
    .from(transactions)
    .where(isNotNull(transactions.source))

  stats.scanned = rows.length

  for (const row of rows) {
    if (!row.payee) {
      stats.skippedNoMatch += 1
      continue
    }
    const booked = new Date(row.occurredAt)
    if (Number.isNaN(booked.getTime())) {
      stats.skippedNoMatch += 1
      continue
    }
    const hit = extractTrueDateFromText(row.payee, booked)
    if (!hit) {
      stats.skippedNoMatch += 1
      continue
    }
    stats.candidates += 1
    // Compare on UTC calendar day so "same day" skips are stable across TZs.
    const bookedDay = booked.toISOString().slice(0, 10)
    const extractedDay = hit.date.toISOString().slice(0, 10)
    if (bookedDay === extractedDay) {
      stats.skippedSameDay += 1
      continue
    }

    console.log(
      `[backfill] ${row.id}  ${bookedDay} → ${extractedDay}  (match=${hit.match})`,
    )

    if (apply) {
      await db
        .update(transactions)
        .set({
          occurredAt: hit.date,
          updatedAt: sql`now()`,
        })
        .where(eq(transactions.id, row.id))
      stats.updated += 1
    }
  }

  console.log('[backfill] done')
  console.log(`  scanned         = ${stats.scanned}`)
  console.log(`  candidates      = ${stats.candidates}`)
  console.log(`  updated         = ${stats.updated}`)
  console.log(`  skipped (no match) = ${stats.skippedNoMatch}`)
  console.log(`  skipped (same day) = ${stats.skippedSameDay}`)
  if (!apply) {
    console.log('[backfill] Dry run — pass --apply to write changes.')
  }

  process.exit(0)
}

main().catch((err) => {
  console.error('[backfill] failed:', err)
  process.exit(1)
})
