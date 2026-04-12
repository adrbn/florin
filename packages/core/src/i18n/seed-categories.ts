export interface SeedCategory {
  name: string
  emoji: string
  isFixed?: boolean
}

export interface SeedCategoryGroup {
  name: string
  kind: 'income' | 'expense'
  color: string
  categories: SeedCategory[]
}

export function getSeedCategories(locale: string): SeedCategoryGroup[] {
  const fr = locale.startsWith('fr')
  return [
    {
      name: fr ? 'Revenus' : 'Income',
      kind: 'income',
      color: '#22c55e',
      categories: [
        { name: fr ? 'Salaires' : 'Wages', emoji: '💸' },
        { name: fr ? 'Gains additionnels' : 'Side Income', emoji: '↩️' },
        { name: 'Ready to Assign', emoji: '🪙' },
      ],
    },
    {
      name: fr ? 'Factures' : 'Bills',
      kind: 'expense',
      color: '#3b82f6',
      categories: [
        { name: fr ? 'Loyer' : 'Rent', emoji: '🏠', isFixed: true },
        { name: fr ? 'Assurances' : 'Insurance', emoji: '📄', isFixed: true },
        { name: fr ? 'Abonnements' : 'Subscriptions', emoji: '🔄', isFixed: true },
      ],
    },
    {
      name: fr ? 'Besoins' : 'Needs',
      kind: 'expense',
      color: '#06b6d4',
      categories: [
        { name: fr ? 'Courses' : 'Groceries', emoji: '🛒' },
        { name: 'Transports', emoji: '🚈' },
      ],
    },
    {
      name: fr ? 'Envies' : 'Wants',
      kind: 'expense',
      color: '#f59e0b',
      categories: [
        { name: fr ? 'Sorties & Restos' : 'Dining Out', emoji: '🍿' },
        { name: fr ? 'Voyages' : 'Travel', emoji: '🏝️' },
        { name: fr ? 'Cadeaux' : 'Gifts', emoji: '🎁' },
        { name: fr ? 'Vêtements' : 'Clothes', emoji: '🧢' },
        { name: fr ? 'Autres' : 'Other', emoji: '⚠️' },
      ],
    },
    {
      name: fr ? 'Épargne' : 'Savings',
      kind: 'expense',
      color: '#a855f7',
      categories: [
        { name: fr ? 'Épargne' : 'Savings', emoji: '💶' },
      ],
    },
  ]
}
