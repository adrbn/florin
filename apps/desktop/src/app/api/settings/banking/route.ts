import { NextResponse } from 'next/server'
import { eq } from 'drizzle-orm'
import { db } from '@/db/client'
import { settings } from '@/db/schema'

export const dynamic = 'force-dynamic'

export async function POST(request: Request) {
  const { appId, keyPath } = await request.json()

  if (!appId || !keyPath) {
    return NextResponse.json({ success: false, error: 'Missing fields' }, { status: 400 })
  }

  await db
    .insert(settings)
    .values({ key: 'eb_app_id', value: appId })
    .onConflictDoUpdate({ target: settings.key, set: { value: appId } })

  await db
    .insert(settings)
    .values({ key: 'eb_private_key_path', value: keyPath })
    .onConflictDoUpdate({ target: settings.key, set: { value: keyPath } })

  return NextResponse.json({ success: true })
}

export async function GET() {
  const appIdRow = await db.select().from(settings).where(eq(settings.key, 'eb_app_id')).get()
  return NextResponse.json({
    configured: Boolean(appIdRow?.value),
    appId: appIdRow?.value ?? null,
  })
}
