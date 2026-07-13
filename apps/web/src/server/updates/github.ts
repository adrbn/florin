import { isNewer } from '@florin/core/lib/version'

const REPO = 'adrbn/florin'
const RELEASES_API = `https://api.github.com/repos/${REPO}/releases/latest`

/**
 * Command the user runs to redeploy the self-hosted container. The web app
 * can't restart itself, so the update modal shows this for a one-copy update.
 * Overridable via env for non-Compose setups (bare Docker, k8s, a script…).
 */
export const UPDATE_COMMAND =
  process.env.FLORIN_UPDATE_COMMAND ?? 'docker compose pull && docker compose up -d'

export interface UpdateStatus {
  /** Latest published version, without a leading `v` (e.g. `"1.2.25"`). */
  version: string
  /** GitHub release page for the changelog. */
  changelogUrl: string
}

/**
 * Ask GitHub for the latest published release and report it only when it is
 * newer than what's running. The `fetch` is cached for 6h via Next's data
 * cache, so at most a few requests a day actually hit GitHub — well under the
 * 60 req/h anonymous limit. Any failure — offline, 403 rate-limit, GitHub down,
 * bad payload — resolves to `null`: a missing update check must stay invisible,
 * never error and never nag with stale data.
 */
export async function getUpdateStatus(
  currentVersion: string,
): Promise<UpdateStatus | null> {
  try {
    const res = await fetch(RELEASES_API, {
      headers: { Accept: 'application/vnd.github+json' },
      next: { revalidate: 21600 },
    })
    if (!res.ok) return null
    const data = (await res.json()) as { tag_name?: string; html_url?: string }
    const tag = data.tag_name
    if (!tag || !isNewer(tag, currentVersion)) return null
    const version = tag.replace(/^florin-/i, '').replace(/^v/i, '')
    return {
      version,
      changelogUrl: data.html_url ?? `https://github.com/${REPO}/releases`,
    }
  } catch {
    return null
  }
}
