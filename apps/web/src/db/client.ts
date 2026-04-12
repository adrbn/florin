import { createPgClient, createPgQueries, createPgMutations } from '@florin/db-pg'
import { env } from '@/server/env'

export const db = createPgClient(env.DATABASE_URL)
export const queries = createPgQueries(db)
export const mutations = createPgMutations(db)
export type DB = typeof db
