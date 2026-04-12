import { NextResponse } from 'next/server'
import { eq } from 'drizzle-orm'
import { db } from '@/db/client'
import { settings } from '@/db/schema'

export const dynamic = 'force-dynamic'

export async function POST(request: Request) {
  const { locale } = await request.json()
  if (!locale) return NextResponse.json({ success: false }, { status: 400 })

  await db
    .insert(settings)
    .values({ key: 'user_locale', value: locale })
    .onConflictDoUpdate({ target: settings.key, set: { value: locale } })

  return NextResponse.json({ success: true })
}
