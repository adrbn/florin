import { NextResponse } from 'next/server'
import { eq } from 'drizzle-orm'
import { db } from '@/db/client'
import { settings } from '@/db/schema'

export async function POST(request: Request) {
  const { currency } = await request.json()
  if (!currency) return NextResponse.json({ success: false }, { status: 400 })

  await db
    .insert(settings)
    .values({ key: 'user_currency', value: currency })
    .onConflictDoUpdate({ target: settings.key, set: { value: currency } })

  return NextResponse.json({ success: true })
}
