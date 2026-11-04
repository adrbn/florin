# Putting Florin on TestFlight

Everything here is done once. The build itself is already prepared — the archive
command below produces what App Store Connect wants, and `Info.plist` already
declares the encryption exemption so the upload does not stop to ask.

## The one-time steps are done

All three were settled on 2026-11-04: Xcode holds the Apple ID that owns team
`2TWQF4T93E`, the app record exists under bundle ID `com.adrbn.florin`, and the
agreements are accepted. An App Store Connect API key sits in
`~/.appstoreconnect/private_keys/` — outside the repository, never committed —
so an upload needs no password and no Organizer.

## Shipping a build

```bash
cd apps/ios
sed -i '' 's/CURRENT_PROJECT_VERSION: <old>/CURRENT_PROJECT_VERSION: <new>/g' project.yml
xcodegen generate --spec project.yml
xcodebuild -project Florin.xcodeproj -scheme Florin -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$PWD/build-archive/Florin.xcarchive" archive
xcodebuild -exportArchive -archivePath "$PWD/build-archive/Florin.xcarchive" \
  -exportOptionsPlist ExportOptions-appstore.plist -exportPath "$PWD/build-export"
xcrun altool --upload-app --type ios -f build-export/Florin.ipa \
  --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
```

`CURRENT_PROJECT_VERSION` appears **twice** in `project.yml` — miss one and the
archive carries the old number. App Store Connect refuses a build number it has
already seen for the same `MARKETING_VERSION`, so it only ever goes up.

Processing takes five to fifteen minutes, after which the build appears in
TestFlight and becomes selectable on the app record.

Signing is pinned by `ExportOptions-appstore.plist` rather than left to Xcode:
the API key carries App Manager, not the Admin role automatic signing wants.
Naming the profiles by hand costs nothing and removes the dependency.

## Beta App Review

External testers — up to 10 000, joining by link, without access to your
developer account — need a Beta App Review on each new version. Internal testers
(100, no review) must be members of your App Store Connect team, which gives
them a login you probably do not want to hand out.

**The one thing that will get this rejected:** a reviewer who picks *Connecter ma
banque* is asked to register their own Enable Banking application on a
third-party website. Nobody reviewing an app does that. Say so in the review
notes:

> Florin holds its ledger on the device; there is no account and no server.
> To review it, choose **"Saisir mes comptes"** on the first screen and add an
> account, or **"Importer un relevé"** with any CSV. The bank-sync path requires
> the tester to register their own free PSD2 application with Enable Banking and
> is not needed to exercise the app.

## Answers you will be asked for

| Question | Answer |
| --- | --- |
| Does the app use encryption? | Yes — exempt. HTTPS and a signature on its own API requests. Already declared in `Info.plist`. |
| Data collection | None. No analytics, no telemetry, no account. Everything stays on the device or on the user's own server. |
| Third-party content | No |
| Sign-in required | No |

## Every 90 days

A TestFlight build expires. Uploading a new one is the same three commands, and
the version has to move — `MARKETING_VERSION` in `project.yml`, which the
lockstep test keeps in step with web and desktop.
