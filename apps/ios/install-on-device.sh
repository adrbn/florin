#!/usr/bin/env bash
# Build the Florin iOS shell and install it on a paired iPhone over Wi-Fi.
#
# Prerequisite (one time, and the one thing that cannot be scripted): Xcode
# must be signed in with the Apple ID that belongs to the signing team, so it
# can mint a development provisioning profile for com.adrbn.florin.
#     Xcode ▸ Settings ▸ Accounts ▸ + ▸ Apple ID
#
# Everything else is headless: no Simulator, no windows, no space switching.
set -euo pipefail

cd "$(dirname "$0")"

DEVICE="${FLORIN_IOS_DEVICE:-}"
if [[ -z "$DEVICE" ]]; then
  # First paired physical device.
  DEVICE=$(xcrun devicectl list devices 2>/dev/null \
    | awk '/physical/ && /available/ {print $(NF-3); exit}')
fi
if [[ -z "$DEVICE" ]]; then
  echo "No paired iPhone found. Plug it in once, or set FLORIN_IOS_DEVICE=<identifier>." >&2
  exit 1
fi
echo "▸ device $DEVICE"

command -v xcodegen >/dev/null && xcodegen generate --spec project.yml >/dev/null

echo "▸ building"
xcodebuild -project Florin.xcodeproj -scheme Florin -configuration Debug \
  -destination "generic/platform=iOS" -derivedDataPath build \
  -allowProvisioningUpdates build

APP=$(find build/Build/Products/Debug-iphoneos -maxdepth 1 -name 'Florin.app' | head -1)
[[ -n "$APP" ]] || { echo "Build produced no app bundle." >&2; exit 1; }

echo "▸ installing $APP"
xcrun devicectl device install app --device "$DEVICE" "$APP"

echo "▸ done — open Florin on the phone and enter your server address."
