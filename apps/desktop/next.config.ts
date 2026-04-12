import type { NextConfig } from 'next'

const config: NextConfig = {
  serverExternalPackages: ['better-sqlite3', 'bindings'],
  webpack: (config, { isServer }) => {
    if (isServer) {
      // Ensure better-sqlite3 and its native binding helper are never
      // bundled by webpack — they must be loaded at runtime from node_modules.
      config.externals = [
        ...(Array.isArray(config.externals) ? config.externals : []),
        ({ request }: { request?: string }, callback: (err?: null, result?: string) => void) => {
          if (request && /^(better-sqlite3|bindings|file-uri-to-path)$/.test(request)) {
            return callback(null, `commonjs ${request}`)
          }
          callback()
        },
      ]
    }
    return config
  },
}

export default config
