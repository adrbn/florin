import { describe, expect, it } from 'vitest'
import webPkg from '../../package.json'
import desktopPkg from '../../../desktop/package.json'

/**
 * Web and desktop ship from the same tag, and each one compares ITS OWN
 * package.json version against the latest GitHub release to decide whether to
 * nag about an update. Bumping only one of them therefore leaves the other
 * permanently showing "Update available" on a fully up-to-date install —
 * which is exactly what happened when v1.2.50 bumped desktop alone.
 */
describe('release versions stay in lockstep', () => {
  it('web and desktop declare the same version', () => {
    expect(webPkg.version).toBe(desktopPkg.version)
  })

  it('the version is a plain semver triple (matches the Florin-v<x.y.z> tag)', () => {
    expect(webPkg.version).toMatch(/^\d+\.\d+\.\d+$/)
  })
})
