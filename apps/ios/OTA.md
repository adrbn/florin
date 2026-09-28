# Installing a build over cellular

`scripts/ota-publish.sh` puts a build on the phone with no cable, no shared
Wi-Fi and no Xcode in front of it. One command here, one tap there. Use it
whenever the phone is not on the same network as this Mac — which, in practice,
is most of the time.

```bash
cd apps/ios
./scripts/ota-publish.sh
```

It prints a URL. Open that URL on the phone, tap **Installer**, then **open the
app once**. The last step is not optional: see *What this does not do*.

## Why devicectl is not an option

`devicectl` only talks to a device CoreDevice discovered itself, over Bonjour,
on the local link. Off that link there is nothing to talk to, and no address
you can hand it instead:

- `devicectl --device <tailnet name>` and `--device <tailnet IP>` both answer
  `CoreDeviceError 1000`, device not found. The `dns_name` the help mentions is
  the `.local` one.
- On the phone's tailnet address, ports 62078, 58783 and 49152 are all closed —
  iOS only runs `remotepairingd` while associated to **Wi-Fi**.

The Tailscale bridges that exist for this (RoamRun, iphone-tailnet-bridge,
`dns-sd -P` + `socat`) replay the phone's `_remotepairing._tcp` announcement
locally. They still need Wi-Fi on the phone, plus a capture of its `identifier`
and `authTag` made beforehand on the same network. None of that helps on a
cellular connection. Apple's own over-the-air install runs over plain HTTPS, so
it does.

## How it works

1. `xcodebuild archive`, then `-exportArchive` with `method: debugging` and a
   `manifest` dictionary. That key is what makes Xcode emit `manifest.plist`
   next to the `.ipa`.
2. The `.ipa`, the manifest, two icon sizes and a small install page are copied
   to a machine on the tailnet.
3. `tailscale serve --bg --set-path /florin <dir>` publishes them over HTTPS,
   with a real certificate — `itms-services://` refuses anything less.
4. The script fetches the manifest back and fails loudly if it is not `200`.

## Settings

Host and destination are personal infrastructure, so they live in
`scripts/ota.env`, which is gitignored:

```sh
FLORIN_OTA_HOST=machine.your-tailnet.ts.net   # what the phone will reach
FLORIN_OTA_SSH=root@machine.your-tailnet.ts.net
FLORIN_OTA_DIR=/opt/florin-ota
```

Pick a machine that is **always on** — the phone may be tapped hours later —
and that runs open-source `tailscaled`. A Mac running the App Store build of
Tailscale cannot do this: `--set-path` fails there with a sandbox error, and
only port proxying works.

Also needed: Xcode signed in to the team that owns the bundle id, and the
phone's UDID in the development profile — the same conditions as any local
install.

## What this does not do

It installs; it does not launch. Nothing outside MDM can start an app on an
iPhone remotely. That matters here because **App Intents are re-registered when
the bundle is replaced**: until the app has run once, Shortcuts cannot find
Florin's action, and a Wallet automation that fires in the meantime records
nothing — silently. The install page says so; say it again when you hand over
the link.

## When it goes wrong

| Symptom | Cause |
| --- | --- |
| `Path serving is not supported on macOS` | App Store build of Tailscale. Use a Linux host. |
| The install page loads, `Installer` does nothing | The manifest was served over something other than valid HTTPS, or its `appURL` does not match where the `.ipa` actually is. |
| "Unable to install" on the phone | The device is not in the provisioning profile, or the profile expired. |
| Everything 200s, nothing installs | Tailscale is off on the phone. The tailnet name resolves nowhere else. |

Do not run `tailscale serve --https=443 off` to clean up: on a host that serves
anything else, that removes every path at once. Remove only `/florin`.
