/** @type {import('next').NextConfig} */
const config = {
  devIndicators: false,
  transpilePackages: ['@florin/core', '@florin/db-sqlite'],
  serverExternalPackages: ['better-sqlite3', 'bindings'],
  async headers() {
    return [
      {
        source: '/(.*)',
        headers: [
          { key: 'X-Frame-Options', value: 'DENY' },
          { key: 'X-Content-Type-Options', value: 'nosniff' },
          { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
        ],
      },
    ]
  },
  webpack: (config, { isServer }) => {
    if (isServer) {
      config.externals = [
        ...(Array.isArray(config.externals) ? config.externals : []),
        ({ request }, callback) => {
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
