# Putting Florin on TestFlight

Everything here is done once. The build itself is already prepared — the archive
command below produces what App Store Connect wants, and `Info.plist` already
declares the encryption exemption so the upload does not stop to ask.

## What only you can do

Three steps need your Apple ID, and nothing else does.

1. **Sign in to Xcode.** Settings → Accounts → the Apple ID that owns team
   `2TWQF4T93E`. Without it, `xcodebuild -exportArchive` reports "No Accounts"
   and cannot create a distribution certificate.
2. **Create the app record.** <https://appstoreconnect.apple.com/apps> → **+** →
   New App. iOS · name **Florin** · primary language French · bundle ID
   `com.adrbn.florin` · SKU `florin-ios`.
3. **Accept the agreements**, if App Store Connect asks. It will, the first time.

## Then

```bash
cd apps/ios
xcodegen generate
xcodebuild archive -project Florin.xcodeproj -scheme Florin \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath /tmp/florin.xcarchive -allowProvisioningUpdates
xcodebuild -exportArchive -archivePath /tmp/florin.xcarchive \
  -exportOptionsPlist ExportOptions-appstore.plist \
  -exportPath /tmp/florin-ipa -allowProvisioningUpdates
```

Upload with Xcode's Organizer (Window → Organizer → Distribute App), or from the
command line with an App Store Connect API key:

```bash
xcrun altool --upload-app -f /tmp/florin-ipa/Florin.ipa -t ios \
  --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
```

Create that key at <https://appstoreconnect.apple.com/access/integrations/api>
(role: App Manager) and drop the `.p8` in `~/.appstoreconnect/private_keys/`.
With it, every future upload is one command and no password.

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
