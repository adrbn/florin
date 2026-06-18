import 'dotenv/config'
import { getSeedCategories } from '@florin/core/i18n/seed-categories'
import { db } from './client'
import { categories, categoryGroups } from './schema'

async function seed() {
  console.log('Seeding default category groups & categories...')

  // Wipe existing seed (idempotent)
  await db.delete(categories)
  await db.delete(categoryGroups)

  // Use the same generic, neutral category set the desktop app ships with.
  // Localised via APP_LOCALE (defaults to English) — no owner-specific
  // categories baked into the public release.
  const locale = process.env.APP_LOCALE ?? 'en'
  const seedGroups = getSeedCategories(locale)

  const groups = await db
    .insert(categoryGroups)
    .values(
      seedGroups.map((g, i) => ({
        name: g.name,
        kind: g.kind,
        displayOrder: i,
        color: g.color,
      })),
    )
    .returning()

  const byName = Object.fromEntries(groups.map((g) => [g.name, g.id]))

  const categoryRows = seedGroups.flatMap((g) =>
    g.categories.map((c, i) => ({
      groupId: byName[g.name]!,
      name: c.name,
      emoji: c.emoji,
      isFixed: c.isFixed ?? false,
      displayOrder: i,
    })),
  )

  await db.insert(categories).values(categoryRows)

  console.log('Seed complete')
  process.exit(0)
}

seed().catch((e) => {
  console.error(e)
  process.exit(1)
})
