'use server'

import { revalidatePath } from 'next/cache'
import { db } from '@/db/client'
import { settings } from '@/db/schema'

/** Partial edit of the tunable app defaults. Any subset of fields may be sent. */
export interface SetAppConfigInput {
  goalTarget?: number
  goalReturnPct?: number
  peaCeiling?: number
}

/** Upsert a single settings-table row, matching the idiom used by setPin(). */
async function upsertSetting(key: string, value: string): Promise<void> {
  await db
    .insert(settings)
    .values({ key, value })
    .onConflictDoUpdate({ target: settings.key, set: { value } })
}

/**
 * Persist the tunable app defaults into the SQLite `settings` table. Each
 * provided value is stored as a string under its settings key; the reader in
 * `@/lib/app-config` resolves them back (falling back to the France/EUR-first
 * defaults). Only fields present in `input` are written.
 */
export async function setAppConfig(input: SetAppConfigInput): Promise<void> {
  if (input.goalTarget !== undefined) {
    await upsertSetting('goal_target', String(input.goalTarget))
  }
  if (input.goalReturnPct !== undefined) {
    await upsertSetting('goal_return_pct', String(input.goalReturnPct))
  }
  if (input.peaCeiling !== undefined) {
    await upsertSetting('pea_ceiling', String(input.peaCeiling))
  }

  revalidatePath('/')
  revalidatePath('/settings')
  revalidatePath('/accounts/[id]', 'page')
}
