import type { NextConfig } from 'next'

const nextConfig: NextConfig = {
  output: 'standalone',
  typedRoutes: true,
  // `postgres` uses Node-only built-ins (net/tls/crypto). Marking it external
  // stops webpack from trying to bundle it for the Edge runtime when it
  // analyzes files like `instrumentation.ts` that can be loaded from either
  // runtime. At runtime we gate the db import behind `NEXT_RUNTIME === 'nodejs'`.
  serverExternalPackages: ['postgres'],
}

export default nextConfig
