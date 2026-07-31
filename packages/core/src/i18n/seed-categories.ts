import { normalizeLocale, type SupportedLocale } from './index'

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

/** One label per supported locale. Adding a language = adding a field here. */
type Label = Record<SupportedLocale, string>

const L = {
  income: { en: 'Income', fr: 'Revenus', nl: 'Inkomsten' },
  wages: { en: 'Wages', fr: 'Salaires', nl: 'Salaris' },
  sideIncome: { en: 'Side Income', fr: 'Gains additionnels', nl: 'Bijverdiensten' },
  readyToAssign: { en: 'Ready to Assign', fr: 'Ready to Assign', nl: 'Klaar om te verdelen' },
  bills: { en: 'Bills', fr: 'Factures', nl: 'Vaste lasten' },
  rent: { en: 'Rent', fr: 'Loyer', nl: 'Huur' },
  insurance: { en: 'Insurance', fr: 'Assurances', nl: 'Verzekeringen' },
  subscriptions: { en: 'Subscriptions', fr: 'Abonnements', nl: 'Abonnementen' },
  needs: { en: 'Needs', fr: 'Besoins', nl: 'Basisbehoeften' },
  groceries: { en: 'Groceries', fr: 'Courses', nl: 'Boodschappen' },
  transport: { en: 'Transport', fr: 'Transports', nl: 'Vervoer' },
  wants: { en: 'Wants', fr: 'Envies', nl: "Extra's" },
  diningOut: { en: 'Dining Out', fr: 'Sorties & Restos', nl: 'Uit eten' },
  travel: { en: 'Travel', fr: 'Voyages', nl: 'Reizen' },
  gifts: { en: 'Gifts', fr: 'Cadeaux', nl: 'Cadeaus' },
  clothes: { en: 'Clothes', fr: 'Vêtements', nl: 'Kleding' },
  other: { en: 'Other', fr: 'Autres', nl: 'Overig' },
  savings: { en: 'Savings', fr: 'Épargne', nl: 'Sparen' },
} satisfies Record<string, Label>

export function getSeedCategories(locale: string): SeedCategoryGroup[] {
  const lang = normalizeLocale(locale)
  const s = (label: Label): string => label[lang]

  return [
    {
      name: s(L.income),
      kind: 'income',
      color: '#22c55e',
      categories: [
        { name: s(L.wages), emoji: '💸' },
        { name: s(L.sideIncome), emoji: '↩️' },
        { name: s(L.readyToAssign), emoji: '🪙' },
      ],
    },
    {
      name: s(L.bills),
      kind: 'expense',
      color: '#3b82f6',
      categories: [
        { name: s(L.rent), emoji: '🏠', isFixed: true },
        { name: s(L.insurance), emoji: '📄', isFixed: true },
        { name: s(L.subscriptions), emoji: '🔄', isFixed: true },
      ],
    },
    {
      name: s(L.needs),
      kind: 'expense',
      color: '#06b6d4',
      categories: [
        { name: s(L.groceries), emoji: '🛒' },
        { name: s(L.transport), emoji: '🚈' },
      ],
    },
    {
      name: s(L.wants),
      kind: 'expense',
      color: '#f59e0b',
      categories: [
        { name: s(L.diningOut), emoji: '🍿' },
        { name: s(L.travel), emoji: '🏝️' },
        { name: s(L.gifts), emoji: '🎁' },
        { name: s(L.clothes), emoji: '🧢' },
        { name: s(L.other), emoji: '⚠️' },
      ],
    },
    {
      name: s(L.savings),
      kind: 'expense',
      color: '#a855f7',
      categories: [{ name: s(L.savings), emoji: '💶' }],
    },
  ]
}
