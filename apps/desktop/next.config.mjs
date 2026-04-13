/** @type {import('next').NextConfig} */
const config = {
  devIndicators: false,
  serverExternalPackages: ['better-sqlite3', 'bindings'],
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
