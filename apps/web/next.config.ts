import path from 'node:path'
import type { NextConfig } from 'next'

const nextConfig: NextConfig = {
  output: 'standalone',
  // Trace up to the monorepo root so standalone output includes
  // workspace packages (@florin/core, @florin/db-pg) copied into
  // .next/standalone/node_modules.
  outputFileTracingRoot: path.join(__dirname, '../..'),
  typedRoutes: true,
  // `postgres` uses Node-only built-ins (net/tls/crypto). Marking it external
  // stops webpack from trying to bundle it for the Edge runtime when it
  // analyzes files like `instrumentation.ts` that can be loaded from either
  // runtime. At runtime we gate the db import behind `NEXT_RUNTIME === 'nodejs'`.
  serverExternalPackages: ['postgres'],
}

export default nextConfig
