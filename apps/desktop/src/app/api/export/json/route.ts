import { NextResponse } from 'next/server'
import { db } from '@/db/client'
import { exportAllDataMutation } from '@florin/db-sqlite'

export const dynamic = 'force-dynamic'

export async function GET() {
  try {
    const payload = await exportAllDataMutation(db)
    const stamp = new Date().toISOString().slice(0, 10)
    return new NextResponse(JSON.stringify(payload, null, 2), {
      headers: {
        'Content-Type': 'application/json',
        'Content-Disposition': `attachment; filename="florin-export-${stamp}.json"`,
      },
    })
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : 'Export failed'
    return NextResponse.json({ error: message }, { status: 500 })
  }
}
