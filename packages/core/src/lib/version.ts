/**
 * Semantic-version helpers shared by the web and desktop update checks. Kept
 * pure and dependency-free so both apps (and the test suite) can import them
 * without pulling in any framework code.
 */

/**
 * Parse a Florin release identifier into a comparable `[major, minor, patch]`
 * tuple. Accepts a bare `"1.2.3"`, a `"v1.2.3"`, or the CI tag form
 * `"Florin-v1.2.3"` (GitHub's `tag_name`). A leading `"Florin-v"` / `"v"` and
 * any trailing pre-release/build suffix (`-beta.1`, `+build.5`) are ignored.
 * Returns `null` when no `x.y.z` version can be recovered, so callers can treat
 * unparseable input as "unknown" rather than guessing.
 */
export function parseVersion(raw: string): [number, number, number] | null {
  if (typeof raw !== 'string') return null
  const cleaned = raw.trim().replace(/^florin-/i, '').replace(/^v/i, '')
  const match = cleaned.match(/^(\d+)\.(\d+)\.(\d+)/)
  if (!match) return null
  return [Number(match[1]), Number(match[2]), Number(match[3])]
}

/**
 * True when `latest` is strictly newer than `current`. Both accept any form
 * {@link parseVersion} understands. If either side is unparseable the result is
 * `false` — we never surface an update prompt we can't actually justify.
 */
export function isNewer(latest: string, current: string): boolean {
  const l = parseVersion(latest)
  const c = parseVersion(current)
  if (!l || !c) return false
  for (let i = 0; i < 3; i++) {
    if (l[i]! > c[i]!) return true
    if (l[i]! < c[i]!) return false
  }
  return false
}
