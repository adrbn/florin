import 'dotenv/config'
import { db } from './client'
import { categories, categoryGroups } from './schema'

async function seed() {
  console.log('Seeding default category groups & categories...')

  // Wipe existing seed (idempotent)
  await db.delete(categories)
  await db.delete(categoryGroups)

  const groups = await db
    .insert(categoryGroups)
    .values([
      { name: 'Revenus', kind: 'income', displayOrder: 0, color: '#22c55e' },
      { name: 'Bills', kind: 'expense', displayOrder: 1, color: '#3b82f6' },
      { name: 'Needs', kind: 'expense', displayOrder: 2, color: '#06b6d4' },
      { name: 'Wants', kind: 'expense', displayOrder: 3, color: '#f59e0b' },
      { name: 'Savings', kind: 'expense', displayOrder: 4, color: '#a855f7' },
    ])
    .returning()

  const byName = Object.fromEntries(groups.map((g) => [g.name, g.id]))

  await db.insert(categories).values([
    // Revenus
    { groupId: byName.Revenus!, name: 'Salaires', emoji: '💸', displayOrder: 0 },
    { groupId: byName.Revenus!, name: 'Gains additionnels', emoji: '↩️', displayOrder: 1 },
    { groupId: byName.Revenus!, name: 'Ready to Assign', emoji: '🪙', displayOrder: 2 },
    // Bills
    { groupId: byName.Bills!, name: 'Rent', emoji: '🏠', isFixed: true, displayOrder: 0 },
    { groupId: byName.Bills!, name: 'Assurances', emoji: '📄', isFixed: true, displayOrder: 1 },
    { groupId: byName.Bills!, name: 'Abonnements', emoji: '🔄', isFixed: true, displayOrder: 2 },
    { groupId: byName.Bills!, name: 'Student loans', emoji: '🎓', isFixed: true, displayOrder: 3 },
    // Needs
    { groupId: byName.Needs!, name: 'Food / Courses', emoji: '🛒', displayOrder: 0 },
    { groupId: byName.Needs!, name: 'Transports', emoji: '🚈', displayOrder: 1 },
    // Wants
    { groupId: byName.Wants!, name: 'Sorties & Restos', emoji: '🍿', displayOrder: 0 },
    { groupId: byName.Wants!, name: 'Bars', emoji: '🥂', displayOrder: 1 },
    { groupId: byName.Wants!, name: 'Voyages', emoji: '🏝️', displayOrder: 2 },
    { groupId: byName.Wants!, name: 'Gifts', emoji: '🎁', displayOrder: 3 },
    { groupId: byName.Wants!, name: 'Coiffeur', emoji: '💇🏼', displayOrder: 4 },
    { groupId: byName.Wants!, name: 'Vêtements & beauté', emoji: '🧢', displayOrder: 5 },
    { groupId: byName.Wants!, name: 'Amazon', emoji: '🧑🏼‍💻', displayOrder: 6 },
    { groupId: byName.Wants!, name: 'PayPal 4x', emoji: '💰', displayOrder: 7 },
    { groupId: byName.Wants!, name: 'Autres', emoji: '⚠️', displayOrder: 8 },
    // Savings
    { groupId: byName.Savings!, name: 'Savings', emoji: '💶', displayOrder: 0 },
  ])

  console.log('Seed complete')
  process.exit(0)
}

seed().catch((e) => {
  console.error(e)
  process.exit(1)
})
