import { readFileSync } from 'node:fs'
import { join } from 'node:path'
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

  /**
   * The iOS client declares its version in xcodegen's project.yml rather than a
   * package.json, which is exactly the kind of second place a bump gets
   * forgotten — the About screen would then claim a version the rest of the
   * deployment left behind. Read it as text: parsing the whole YAML for one
   * scalar would mean a dependency this repo does not otherwise need.
   */
  it('the iOS app declares the same version', () => {
    const project = readFileSync(join(__dirname, '../../../ios/project.yml'), 'utf8')
    const marketing = project.match(/MARKETING_VERSION:\s*"?([\d.]+)"?/)
    expect(marketing?.[1]).toBe(webPkg.version)
  })
})
