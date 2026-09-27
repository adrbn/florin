#!/bin/bash
# Publie un build que le téléphone peut installer de n'importe où, en 4G/5G.
#
# Pas de câble, pas de Wi-Fi commun, pas de Xcode côté téléphone : l'IPA est
# servie en HTTPS sur le tailnet, et iOS l'installe par son mécanisme OTA
# (itms-services). Il suffit que Tailscale soit actif sur le téléphone.
#
# Réglages locaux dans scripts/ota.env (non versionné) :
#   FLORIN_OTA_HOST  nom tailnet de la machine qui sert (ex. serveur.exemple.ts.net)
#   FLORIN_OTA_SSH   cible ssh de cette machine (ex. root@serveur.exemple.ts.net)
#   FLORIN_OTA_DIR   répertoire servi sur cette machine (défaut /opt/florin-ota)
set -euo pipefail

cd "$(dirname "$0")/.."
[ -f scripts/ota.env ] && . scripts/ota.env
HOST="${FLORIN_OTA_HOST:?renseigne FLORIN_OTA_HOST dans scripts/ota.env}"
TARGET="${FLORIN_OTA_SSH:?renseigne FLORIN_OTA_SSH dans scripts/ota.env}"
DIR="${FLORIN_OTA_DIR:-/opt/florin-ota}"
BASE="https://$HOST/florin"

ARCHIVE="${TMPDIR:-/tmp}/Florin.xcarchive"
EXPORT="${TMPDIR:-/tmp}/florin-export"
STAGE="${TMPDIR:-/tmp}/florin-ota-stage"

command -v xcodegen >/dev/null 2>&1 && xcodegen generate --spec project.yml >/dev/null
rm -rf "$ARCHIVE" "$EXPORT" "$STAGE"
mkdir -p "$EXPORT" "$STAGE"

cat > "$EXPORT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>debugging</string>
  <key>signingStyle</key><string>automatic</string>
  <key>destination</key><string>export</string>
  <key>stripSwiftSymbols</key><true/>
  <key>manifest</key><dict>
    <key>appURL</key><string>$BASE/Florin.ipa</string>
    <key>displayImageURL</key><string>$BASE/icon-57.png</string>
    <key>fullSizeImageURL</key><string>$BASE/icon-512.png</string>
  </dict>
</dict></plist>
PLIST

echo "→ archive"
xcodebuild archive -quiet -project Florin.xcodeproj -scheme Florin \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" -allowProvisioningUpdates

echo "→ export"
xcodebuild -exportArchive -quiet -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$EXPORT/ExportOptions.plist" -exportPath "$EXPORT" \
  -allowProvisioningUpdates

VERSION=$(/usr/libexec/PlistBuddy -c \
  'Print :ApplicationProperties:CFBundleShortVersionString' "$ARCHIVE/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c \
  'Print :ApplicationProperties:CFBundleVersion' "$ARCHIVE/Info.plist")

cp "$EXPORT/Florin.ipa" "$EXPORT/manifest.plist" "$STAGE/"
ICON=Florin/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
sips -Z 512 "$ICON" --out "$STAGE/icon-512.png" >/dev/null
sips -Z 57  "$ICON" --out "$STAGE/icon-57.png"  >/dev/null

cat > "$STAGE/index.html" <<HTML
<!doctype html><html lang="fr"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Florin $VERSION</title>
<style>
 :root{color-scheme:light dark}
 body{font:17px/1.5 -apple-system,system-ui,sans-serif;margin:0;min-height:100vh;
      display:grid;place-content:center;gap:22px;text-align:center;padding:24px}
 img{width:96px;height:96px;border-radius:22px;justify-self:center}
 a{display:inline-block;padding:14px 30px;border-radius:14px;background:#0a7;
   color:#fff;text-decoration:none;font-weight:600}
 p{color:#888;margin:0;font-size:15px}
</style>
<img src="icon-512.png" alt="">
<div><strong>Florin $VERSION</strong><br><p>build $BUILD</p></div>
<a href="itms-services://?action=download-manifest&amp;url=$BASE/manifest.plist">Installer</a>
<p>Puis ouvre l'app une fois : c'est ce qui réarme l'action Apple&nbsp;Pay.</p>
</html>
HTML

echo "→ envoi vers $TARGET:$DIR"
ssh -o ConnectTimeout=20 "$TARGET" "mkdir -p '$DIR'"
scp -q "$STAGE"/Florin.ipa "$STAGE"/manifest.plist "$STAGE"/icon-512.png \
       "$STAGE"/icon-57.png "$STAGE"/index.html "$TARGET:$DIR/"
ssh "$TARGET" "tailscale serve --bg --set-path /florin '$DIR'" >/dev/null

code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 "$BASE/manifest.plist")
[ "$code" = 200 ] || { echo "ÉCHEC : le manifeste répond $code" >&2; exit 1; }

echo
echo "Florin $VERSION (build $BUILD) publié — $BASE/"
echo "Sur le téléphone, Tailscale actif, n'importe quel réseau : ouvre ce lien,"
echo "installe, puis lance l'app une fois."
