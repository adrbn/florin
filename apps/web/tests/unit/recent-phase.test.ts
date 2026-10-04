import { describe, expect, it } from 'vitest'
// Pas dans la carte d'exports du paquet ; on lit la source, comme le harnais.
import { listTransactionsQuery } from '../../../../packages/db-sqlite/src/queries/transactions'
import {
  isoOffsetDays,
  makeForecastDb,
  seedAccount,
  seedTx,
  todayIso,
  type ForecastTestContext,
} from './forecast-test-helpers'

/**
 * Un grand livre qui contient les quatre états possibles d'une ligne :
 * comptabilisée, annoncée pour plus tard, en attente côté banque, et passée
 * mais à trier.
 */
function seedEveryPhase(ctx: ForecastTestContext): string {
  const account = seedAccount(ctx, { name: 'Compte courant' })
  seedTx(ctx, { accountId: account, occurredAt: isoOffsetDays(-2), amount: -12.5, payee: 'Réglée' })
  seedTx(ctx, { accountId: account, occurredAt: todayIso(), amount: -4.1, payee: "Réglée aujourd'hui" })
  seedTx(ctx, { accountId: account, occurredAt: isoOffsetDays(9), amount: -30, payee: 'Annoncée' })
  seedTx(ctx, {
    accountId: account,
    occurredAt: isoOffsetDays(-1),
    amount: -8,
    payee: 'À trier',
    needsReview: true,
  })
  ctx.raw
    .prepare(
      `INSERT INTO transactions (id, account_id, occurred_at, amount, status, source, payee, is_pending)
       VALUES ('d4444444-4444-4444-8444-444444444401', ?, ?, -6, 'pending', 'manual', 'En attente', 1)`,
    )
    .run(account, isoOffsetDays(-3))
  return account
}

describe('les deux phases de « Dernières opérations »', () => {
  it("ne garde que ce qui a eu lieu, côté réglé", async () => {
    const ctx = makeForecastDb()
    seedEveryPhase(ctx)
    const rows = await listTransactionsQuery(ctx.db, { limit: 50, phase: 'settled' })
    expect(rows.map((r) => r.payee).sort()).toEqual(["Réglée", "Réglée aujourd'hui"])
  })

  it('met tout le reste en attente, annonces comprises', async () => {
    const ctx = makeForecastDb()
    seedEveryPhase(ctx)
    const rows = await listTransactionsQuery(ctx.db, { limit: 50, phase: 'waiting' })
    expect(rows.map((r) => r.payee).sort()).toEqual(['Annoncée', 'À trier', 'En attente'].sort())
  })

  /*
   * C'est cette propriété qui autorise l'API à coller les deux listes bout à
   * bout sans dédoublonner : aucune ligne ne manque, aucune ne compte double.
   */
  it('les deux phases partitionnent le grand livre', async () => {
    const ctx = makeForecastDb()
    seedEveryPhase(ctx)
    const [all, settled, waiting] = await Promise.all([
      listTransactionsQuery(ctx.db, { limit: 50 }),
      listTransactionsQuery(ctx.db, { limit: 50, phase: 'settled' }),
      listTransactionsQuery(ctx.db, { limit: 50, phase: 'waiting' }),
    ])
    const ids = [...settled, ...waiting].map((r) => r.id)
    expect(new Set(ids).size).toBe(ids.length)
    expect(ids.sort()).toEqual(all.map((r) => r.id).sort())
  })

  /*
   * Le symptôme d'origine : une annonce est datée dans le futur, donc le tri
   * par date la met devant, et douze annonces suffisaient à cacher tout ce
   * qui venait réellement de se passer.
   */
  it("une annonce ne prend plus la place d'une opération réglée", async () => {
    const ctx = makeForecastDb()
    const account = seedAccount(ctx, { name: 'Compte courant' })
    for (let i = 1; i <= 12; i += 1) {
      seedTx(ctx, { accountId: account, occurredAt: isoOffsetDays(i), amount: -10, payee: `Annonce ${i}` })
    }
    seedTx(ctx, { accountId: account, occurredAt: isoOffsetDays(-1), amount: -5, payee: 'Hier' })

    const naive = await listTransactionsQuery(ctx.db, { limit: 12 })
    expect(naive.some((r) => r.payee === 'Hier')).toBe(false)

    const settled = await listTransactionsQuery(ctx.db, { limit: 12, phase: 'settled' })
    expect(settled.map((r) => r.payee)).toEqual(['Hier'])
  })
})
