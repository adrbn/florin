# Security policy

Florin holds bank transactions and, on the iPhone and the Mac, the private key that signs
its requests to Enable Banking. Reports that help keep either safe are very welcome.

## Reporting a vulnerability

**Please do not open a public issue.** Report it privately through GitHub instead:
[**Report a vulnerability**](https://github.com/adrbn/florin/security/advisories/new).
Only the maintainer can read it.

Include what you found, the platform and version, and the steps to reproduce it. You will
get an acknowledgement within a week, and a fix or a plan once the issue is understood.
Credit in the release notes is yours if you want it.

## Supported versions

Only the latest release of each app receives security fixes: the Mac app and the web
build from the newest [release](https://github.com/adrbn/florin/releases/latest), and
the iPhone app's current version.

## What is in scope

- Anything that exposes ledger data outside the device or server it lives on
- The handling of the Enable Banking signing key — generation, storage, use
- The bank consent flow and its redirect (`apps/site`, the Associated Domain)
- Authentication of the self-hosted web app
- The backup export and restore

## What is not

- Attacks that need an unlocked device already in the attacker's hands. The amount-hiding
  shake gesture is a curtain against someone looking over your shoulder, not a lock —
  Face ID is the lock.
- A self-hosted server exposed to the internet without the reverse proxy and TLS the
  README asks for.
- Vulnerabilities in Enable Banking or in a bank's own consent pages — report those to
  them.
