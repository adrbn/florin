<p align="center">
  <img src="apps/desktop/public/icon.png" width="128" alt="Florin" />
</p>

<h1 align="center">Florin</h1>

<p align="center">
  <strong>Personal finance that stays on your own machines.</strong><br>
  A native Mac app, a native iPhone app, and a self-hostable web app — one codebase, no SaaS in the middle.
</p>

<p align="center">
  <a href="https://github.com/adrbn/florin/releases/latest"><img src="https://img.shields.io/github/v/release/adrbn/florin?sort=semver&filter=Florin-v*&label=release&color=6c5ce7" alt="Latest release"></a>
  <a href="https://github.com/adrbn/florin/actions/workflows/florin-release.yml"><img src="https://img.shields.io/github/actions/workflow/status/adrbn/florin/florin-release.yml?label=build" alt="Build"></a>
  <img src="https://img.shields.io/badge/platforms-macOS%20%C2%B7%20iOS%20%C2%B7%20self--hosted-111" alt="Platforms">
  <a href="./LICENSE"><img src="https://img.shields.io/badge/license-AGPL--3.0-green" alt="License"></a>
</p>

---

## Download

| | |
| --- | --- |
| **macOS** | [`Florin-*-arm64.dmg`](https://github.com/adrbn/florin/releases/latest) — signed, notarised, auto-updating |
| **iPhone** | [`Florin-*-unsigned.ipa`](https://github.com/adrbn/florin/releases/latest) — sideload with [AltStore](https://altstore.io), [SideStore](https://sidestore.io) or [Sideloadly](https://sideloadly.io); see [iPhone](#iphone-appsios) |
| **Self-hosted** | [`Florin-*-server.tar.gz`](https://github.com/adrbn/florin/releases/latest) — `docker compose up -d`; see [Install — Web](#install--web-self-host) |

Nothing to sign up for, on any of them. There is no Florin account, because there is no
Florin server.

## Why

- **Your data stays on your machines.** No SaaS middleman, no analytics, no telemetry, no
  account to create. The Mac and the iPhone hold their own SQLite ledger; the web build
  runs on hardware you control.
- **Real bank sync, under your own credentials.** PSD2 access to 2 000+ European banks via
  [Enable Banking](https://enablebanking.com/) — you register your own free application, so
  the consent is between you and your bank rather than through anyone's shared key.
- **Arithmetic that matches the bank.** A loan's *capital restant dû* comes from a real
  amortisation schedule, on the periodic rate recovered from your contract rather than the
  advertised one — to the euro. A savings rate counts complete months only. When a figure
  cannot be computed honestly, the app says so instead of showing a zero.
- **A budgeting workflow, not a chart gallery.** Category groups, a review queue that learns
  from how you file your own history, monthly plan, and a month-end projection that widens
  when it should.

## Features

**The month you are in**
- A dashboard that leads with what is left to spend, and how long it has to last
- A month-end projection that widens when the month is young and narrows as it fills, rather than pretending to know on the 3rd
- A plan in category groups, with a review queue that learns from how you file your own history — and offers its guess rather than filing silently when it is unsure
- Bring last month's amounts forward instead of retyping them

**Money that is not cash**
- Loans on a real amortisation schedule: the periodic rate is recovered from your contract, so *capital restant dû* matches the bank rather than approximating it, and every instalment moves it
- Holdings with cost basis and unrealised gain, contributed-versus-market split, live quotes fetched by symbol alone
- Net worth over time, asset allocation, rolling savings rate over complete months

**Getting money in**
- PSD2 bank sync through your own Enable Banking application
- CSV and OFX import that reads what French, German and English banks actually export — preamble lines, semicolons, comma decimals, and a date order it works out from the file
- Manual entry, transfers between your own accounts, and a prompt when money leaves for an account the bank does not sync

**Living with it**
- Face ID over the whole ledger; shake to hide every amount
- A home-screen widget with what is left and the daily pace it allows
- One notification a morning, after the bank has published overnight — never one per transaction
- Export a copy you can read with any SQLite tool, and restore it onto a new phone
- English, French and Dutch throughout

## Platforms

### Desktop (`apps/desktop`)

Native macOS app. Zero config, one-click install.

- Menu bar tray widget (net worth, burn rate, recent transactions)
- PIN lock, onboarding wizard
- Signed, notarized, and auto-updating via GitHub Releases
- All data in `~/Library/Application Support/@florin/desktop/florin.db`

### iPhone (`apps/ios`)

Native SwiftUI app. Runs entirely on the phone — its own SQLite ledger, its own
bank sync, no server required — or as a client of your Florin server, switched
in Settings.

- The full app on device: dashboard, plan, activity, analysis, transfers between
  your own accounts, manual entry
- Bank sync straight from the phone: the RSA key is generated in the iOS
  keychain as `WhenUnlockedThisDeviceOnly`, so it never syncs and never travels
  to another device, and the bank's consent screen opens in
  `ASWebAuthenticationSession`
- Categorises new transactions from how you have filed your own history — no
  rules to write, no data sent anywhere
- Background refresh with one summary notification, not one per transaction
- Ledger in `Library/Application Support/Florin/florin.db`, included in the
  iPhone's iCloud backup, plus an export/restore pair for moving to a new phone
- No App Store build: AGPL-3.0 and the App Store terms do not mix, and Enable
  Banking requires one registered application per person.

**Install it.** Every release carries `Florin-<version>-unsigned.ipa`. It is
unsigned on purpose — a build signed with someone else's certificate installs on
nobody else's phone — so it is re-signed on the way in, with your own Apple ID,
by [AltStore](https://altstore.io), [SideStore](https://sidestore.io) or
[Sideloadly](https://sideloadly.io). Nothing to pay and no developer account
needed; a free Apple ID re-signs for seven days at a time, a paid one for a year.

Two things a sideloaded build will not do, both because of what a free Apple ID
is allowed to declare rather than anything in the app:

- **Bank sync needs a domain you control.** The consent screen returns through an
  `https` callback, which iOS only routes to an app whose Associated Domains
  entitlement matches a file hosted on that domain — and that entitlement needs a
  paid account. The file also names one team and one bundle id, so it must be
  yours: host your own (see `apps/site/.well-known/apple-app-site-association`)
  and point `BankingFlow.redirectHost` and `project.yml` at it. You are
  registering your own Enable Banking application with your own redirect URL
  anyway.
- **Notifications and background refresh** are similarly gated behind
  capabilities a personal team cannot declare.

Everything else works: manual entry, transfers, categories, budgets, the
dashboard, import/export — or point it at your own Florin server, and the phone
becomes a client of it.

**TestFlight.** The signed route, and the better one if you have an Apple
Developer membership: properly signed, no seven-day expiry, updates arrive on
their own — and bank sync actually works, because the build carries the
Associated Domains entitlement a re-signed one cannot. External testers join by
link, up to 10 000, without joining your developer team; each build passes a
Beta App Review and expires after 90 days. The steps, the answers App Store
Connect asks for, and the review note that keeps a first submission from being
rejected are in [`apps/ios/TESTFLIGHT.md`](apps/ios/TESTFLIGHT.md).

**Build it yourself** with Xcode 26 or newer:

```bash
cd apps/ios && xcodegen generate && open Florin.xcodeproj
```

Select your own team in Signing & Capabilities and run it on a device. The
deployment floor is iOS 17.4; the glass material is behind `#available(iOS 26)`.

### Web (`apps/web`)

Single-admin Next.js 15 + Postgres stack behind a reverse proxy of your choice.

- One `docker compose up -d`
- PWA-installable on mobile
- Legacy YNAB-style XLSX importer for migrations

## Install — Desktop

Download the latest `.dmg` from [Releases](https://github.com/adrbn/florin/releases), drag Florin to Applications, launch. Onboarding walks you through language, categories, and your first account.

Released builds are **signed with a Developer ID certificate and notarized by Apple**, so they open without Gatekeeper warnings and update in place — no `xattr` dance. Updates arrive automatically: Florin checks GitHub Releases on launch and every 6 hours, downloads in the background, and shows a "Restart to install" pill in the sidebar. (Quitting the app also installs a pending update.)

### Build the desktop app from source

Requires **Node 22** — `better-sqlite3` has no prebuilt binary for newer Node majors and its native build fails there. CI pins 22 too.

```bash
pnpm install
pnpm --filter @florin/desktop run pack
```

`pack` builds the Electron main process (esbuild) and the Next.js app, then runs `electron-builder`, which rebuilds the `better-sqlite3` native module against Electron for the target arch before packaging. The `.dmg` lands in `apps/desktop/dist/` (`Florin-<version>-<arch>.dmg`).

Local builds are **unsigned** — signing and notarization only happen in CI, where the `CSC_*` / `APPLE_*` secrets exist. To run an unsigned local build, right-click → **Open**, or `xattr -dr com.apple.quarantine /Applications/Florin.app`.

Releases are cut by pushing a `Florin-v*` tag (matching the `version` in **both** `apps/web/package.json` and `apps/desktop/package.json`); the workflow builds both arches, signs, notarizes, and attaches them to a GitHub Release. Wait for the run to finish before expecting auto-update to see it — a release whose `latest-mac.yml` hasn't uploaded yet shadows the previous one and update checks fail until it does.

### Forking / self-distributing

If you fork Florin and ship your own desktop builds, change `publish.owner` and `publish.repo` in `apps/desktop/electron-builder.yml` to point at **your** GitHub repo before distributing. Otherwise the built-in auto-updater will check the upstream `adrbn/florin` releases and try to update users onto the upstream binaries.

## Install — Web (self-host)

Needs Docker, plus **Node 22** + pnpm for the password-hash and migrate steps (`pnpm install` resolves the whole workspace, and `better-sqlite3` won't compile on newer Node majors).

```bash
git clone https://github.com/adrbn/florin.git
cd florin
cp .env.example .env
openssl rand -base64 32   # → DB_PASSWORD
openssl rand -base64 32   # → NEXTAUTH_SECRET
```

Hash your admin password, then edit `.env`:

```bash
cd apps/web && pnpm install
pnpm tsx scripts/hash-password.ts "your-strong-password"
```

Copy the hash into `.env` as `ADMIN_PASSWORD_HASH` — escape every `$` with `\$` so Docker Compose doesn't expand them.

```bash
cd ..
docker compose up -d
cd apps/web && pnpm drizzle-kit migrate && pnpm tsx src/db/seed.ts
```

Visit `http://localhost:3000`. **Do not expose Florin to the public internet without a reverse proxy** (Caddy, Traefik, Tailscale Serve, etc.) — put TLS in front.

## Link a bank (Enable Banking)

1. Register at <https://enablebanking.com/>, create an application.
2. Generate an RSA key pair and upload the public key:
   ```bash
   openssl genrsa -out enablebanking-private.pem 2048
   openssl rsa -in enablebanking-private.pem -pubout -out enablebanking-public.pem
   ```
3. Add the redirect URI in Enable Banking:
   - Desktop: `https://127.0.0.1:3847/api/banking/callback`
   - Web: `https://florin.yourdomain.tld/api/banking/callback`
4. Configure credentials:
   - **Desktop:** Settings → Bank Sync → enter App ID and import the `.pem`. The key is copied into Application Support and never leaves your machine.
   - **Web:** set `ENABLE_BANKING_APP_ID`, `ENABLE_BANKING_PRIVATE_KEY_PATH`, `ENABLE_BANKING_REDIRECT_URL` in `.env`.

### Desktop: connect your bank (no self-hosting, no terminal)

Running the `.dmg`? You don't self-host anything, and you don't need a terminal. Florin has no shared bank connection, so each person registers their own **free** Enable Banking application once — it stays entirely yours: the private key is generated and kept on your Mac, and your bank consents run through your own account, not anyone else's.

1. In Florin: **Settings → Bank Sync → Generate a key**. Florin creates the key pair on your machine and shows the **public** key — click **Copy**.
2. Sign up at <https://enablebanking.com/> and **create an application** (the free tier is enough). Paste the copied **public key** into it, and add this **redirect URI**:
   `https://127.0.0.1:3847/api/banking/callback`
3. Copy the application's **App ID**, paste it back into Florin's Bank Sync screen, and **Save**.

That's it — "Synchroniser" now links your bank. Prefer not to bother? Skip it and use Florin with **manual entry + CSV/OFX import** ([below](#import-data)) — everything works without Enable Banking.

## Configure

Florin's defaults are France/EUR-first. Every assumption is a knob — on **web** they're env vars in `.env`, on **desktop** the same settings live in Settings → App (no env needed).

| Setting | Default | What it does |
| --- | --- | --- |
| `APP_CURRENCY` | `EUR` | Display currency + number formatting |
| `APP_GOAL_TARGET` | `100000` | Long-term wealth target on the goal card |
| `APP_GOAL_RETURN_PCT` | `7` | Assumed net annual return for the projection |
| `APP_PEA_CEILING` | `150000` | Contribution cap for a tax wrapper (France's PEA). **Set `0` to hide the gauge** if your country has no such cap |
| `APP_DCA_MONTHLY` | *(blank)* | Planned monthly investment. Blank = inferred from your history |
| `PRICE_PROVIDER` | `none` | `yahoo` opts into live quotes for holdings. Off by default — no outbound calls unless you ask |

Live prices are **opt-in**: with `PRICE_PROVIDER=none` the refresh job is a no-op and Florin never talks to a quote API. Set `yahoo` and give each holding a symbol (e.g. `CW8.PA`) to have market values refresh in the background.

## Import data

Drag-and-drop CSV / OFX / QFX onto an account's detail page — column mapping, European date and number formats are auto-detected.

For migrations from a YNAB-style spreadsheet (web only):

```bash
cd apps/web
node --env-file=.env --import tsx scripts/import-legacy-xlsx.ts /path/to/finances.xlsx
```

Idempotent — safe to re-run.

## Backup

**Web (Postgres):**

```bash
docker exec florin-db pg_dump -U florin -d florin --no-owner --no-privileges \
  | gzip -9 > "backups/florin-$(date -u +%Y%m%dT%H%M%SZ).sql.gz"
```

**Desktop (SQLite):** copy `~/Library/Application Support/@florin/desktop/florin.db` — single file, best taken with the app closed. JSON export also available in Settings → Data.

**iPhone:** the ledger is part of the iPhone's iCloud backup, which covers losing
the phone and is invisible from inside the app — iOS tells apps neither whether
backups are on nor when the last one ran. For a copy you can see, Settings →
Sauvegarde → **Exporter une copie** writes a plain SQLite file (readable by any
SQLite tool) into the app's Documents folder, visible in Files under "Florin" and
offered to the share sheet. **Restaurer une copie** replaces the ledger with a
file's contents — that is what moves everything to a new phone, and it is offered
during onboarding so a fresh install does not have to invent an account first.
The bank connection is deliberately not in the file — a PSD2 session restored
onto another phone is a dead session — and the signing key could not be there
anyway: it lives in the keychain marked `ThisDeviceOnly`, which is precisely a
promise never to appear on a second device. Reconnect the bank on the new phone.

## Status

Built and used daily by one person on their own money, which is the only test bed it has
and a fairly demanding one. Web and desktop ship from the same tag and share a test suite;
the iPhone app has its own. The figures that would be embarrassing to get wrong — a loan's
remaining capital, a savings rate, a month-end projection — are checked against real bank
statements rather than against themselves.

What it is not: a product with support, a hosted service, or an App Store download. See
[Licence](#licence) for why the last one is unlikely.

## Repo layout

```
apps/
  web/              Next.js 15 + Drizzle + Postgres (Docker)
  desktop/          Electron 35 + Next.js 15 + SQLite
    main/           Main process (TS → esbuild → CJS)
    tray-ui/        Menu bar widget (static HTML)
  ios/              SwiftUI + raw SQLite, XcodeGen project
    Florin/Local/   On-device ledger: schema, queries, categoriser, backup
    Florin/Banking/ Enable Banking client, key generation, consent flow
packages/
  core/             Shared UI, types, i18n, formatters
  db-pg/            Postgres client, queries, mutations
  db-sqlite/        SQLite client, queries, mutations
compose.yaml
```

## Development

**Node 22 + pnpm.** `better-sqlite3` ships no prebuilt binary for newer Node majors and fails to compile against them, so `pnpm install` breaks the whole workspace on Node 26. CI pins 22.

```bash
# Web
make install && make dev
make test   lint   migrate   seed

# Desktop
cd apps/desktop && pnpm dev
```

`packages/db-pg` and `packages/db-sqlite` are deliberate twins — same schema shape and query surface over different drivers. A query or sync fix almost always has to land in **both**, and likewise for the `apps/web` / `apps/desktop` server actions that wrap them.

## Contributing

Issues and pull requests are welcome. Two things worth knowing before you open one:

- `packages/db-pg` and `packages/db-sqlite` are deliberate twins. A query or sync fix
  almost always belongs in **both**, and a version bump belongs in web, desktop and iOS
  together — a test fails the build otherwise.
- Figures are expected to be checked against something real. A change to how a number is
  computed should come with a test that pins it to a statement, a documented case, or an
  independent calculation.

## Licence

[AGPL-3.0](./LICENSE). Self-host, fork, modify and redistribute freely — any hosted
derivative must publish its source, which is the point: a Florin someone runs for you
should be a Florin you can read.

This is also why there is no App Store build. The App Store's terms and the GPL family do
not mix for redistributors, and Enable Banking expects one registered application per
person rather than a shared one. Build it yourself, or take the signed Mac app and the
sideloadable iPhone build from [Releases](https://github.com/adrbn/florin/releases).
