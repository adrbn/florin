import { z } from 'zod'

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
  DATABASE_URL: z.url(),
  NEXTAUTH_SECRET: z.string().min(32, 'NEXTAUTH_SECRET must be at least 32 chars'),
  NEXTAUTH_URL: z.url().default('http://localhost:3000'),
  ADMIN_EMAIL: z
    .union([z.email(), z.literal('')])
    .optional()
    .transform((v) => (v === '' ? undefined : v)),
  ADMIN_PASSWORD_HASH: z
    .string()
    .optional()
    .transform((v) => (v === '' ? undefined : v)),
  APP_BASE_URL: z.url().default('http://localhost:3000'),
  LOG_LEVEL: z.enum(['debug', 'info', 'warn', 'error']).default('info'),
  // ============ Enable Banking (PSD2 Open Banking) ============
  // All optional — Florin runs without bank linking until these are set.
  // Treat empty strings the same as missing so that bare .env templates do
  // not break the schema.
  ENABLE_BANKING_APP_ID: z
    .string()
    .optional()
    .transform((v) => (v === '' ? undefined : v)),
  ENABLE_BANKING_PRIVATE_KEY_PATH: z
    .string()
    .optional()
    .transform((v) => (v === '' ? undefined : v)),
  ENABLE_BANKING_REDIRECT_URL: z
    .union([z.url(), z.literal('')])
    .optional()
    .transform((v) =>
      v === '' || v === undefined ? 'https://localhost:3000/api/banking/callback' : v,
    ),
})

export type Env = z.infer<typeof envSchema>

const parsed = envSchema.safeParse(process.env)

if (!parsed.success) {
  console.error('Invalid environment variables:', parsed.error.flatten().fieldErrors)
  throw new Error('Invalid environment variables — fix .env and restart')
}

export const env: Env = parsed.data
