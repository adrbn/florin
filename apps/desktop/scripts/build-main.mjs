import { buildSync } from 'esbuild'

buildSync({
  entryPoints: ['main/index.ts'],
  bundle: true,
  platform: 'node',
  outfile: 'dist-main/index.cjs',
  format: 'cjs',
  external: ['electron', 'better-sqlite3', 'electron-updater', 'next', '../src/*'],
  target: 'node22',
})

buildSync({
  entryPoints: ['main/preload.ts'],
  bundle: true,
  platform: 'node',
  outfile: 'dist-main/preload.cjs',
  format: 'cjs',
  external: ['electron'],
  target: 'node22',
})
