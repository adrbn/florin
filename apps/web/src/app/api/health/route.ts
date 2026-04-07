import { NextResponse } from 'next/server'
import { env } from '@/server/env'

export function GET() {
  return NextResponse.json({ status: 'ok', env: env.NODE_ENV })
}
