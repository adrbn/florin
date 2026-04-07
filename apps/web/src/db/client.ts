import { drizzle } from 'drizzle-orm/postgres-js'
import postgres from 'postgres'
import { env } from '@/server/env'
import * as schema from './schema'

const queryClient = postgres(env.DATABASE_URL, { max: 10 })

export const db = drizzle(queryClient, { schema })
export type DB = typeof db
