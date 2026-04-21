<p align="center">
  <img src="apps/desktop/public/icon.png" width="128" alt="Florin" />
</p>

<h1 align="center">Florin</h1>

<p align="center">
  Privacy-first personal finance — a native macOS app and a self-hostable web app.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/license-AGPL--3.0-green" alt="License">
  <img src="https://img.shields.io/badge/stack-Next.js%2015%20%C2%B7%20Electron%2035%20%C2%B7%20Drizzle-111" alt="Stack">
</p>

---

## Why

- **Your data stays on your machine.** No SaaS middleman, no analytics, no telemetry.
- **Real bank sync via PSD2.** Connects to 2 000+ EU banks through [Enable Banking](https://enablebanking.com/) — you register your own free app and keep the credentials.
- **YNAB-style workflow.** Category groups (Needs / Wants / Bills / Savings / Income), a review queue for new imports, auto-categorization rules, monthly plan.
- **Two shapes, one codebase.** Native macOS desktop (Electron + SQLite) or self-hosted web (Docker + Postgres).

## Features

- Multi-account tracking: checking, savings, cash, loans, brokerage
- Dashboard: net worth, burn rate, safety gauge, monthly margin, 12-month patrimony chart with forecast, category breakdown
- Review queue with bulk approve / recategorize / delete
- Reflect analytics: 52-week spending heatmap, rolling savings rate, subscriptions radar, "if I stopped X" counterfactual, net worth over time
- CSV / OFX / QFX import with auto column mapping
- PDF monthly summary export
- Command palette (⌘K), keyboard shortcuts, dark mode, English + French

### Desktop (`apps/desktop`)

Native macOS app. Zero config, one-click install.

- Menu bar tray widget (net worth, burn rate, recent transactions)
- PIN lock, onboarding wizard
- Auto-updater via GitHub Releases
- All data in `~/Library/Application Support/Florin/florin.db`

### Web (`apps/web`)

Single-admin Next.js 15 + Postgres stack behind a reverse proxy of your choice.

- One `docker compose up -d`
- PWA-installable on mobile
- Legacy YNAB-style XLSX importer for migrations

## Install — Desktop

Download the latest `.dmg` from [Releases](https://github.com/adrbn/florin/releases), drag Florin to Applications, launch. Onboarding walks you through language, categories, and your first account.

## Install — Web (self-host)

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

**Desktop (SQLite):** copy `~/Library/Application Support/Florin/florin.db` — single file. JSON export also available in Settings → Data.

## Repo layout

```
apps/
  web/              Next.js 15 + Drizzle + Postgres (Docker)
  desktop/          Electron 35 + Next.js 15 + SQLite
    main/           Main process (TS → esbuild → CJS)
    tray-ui/        Menu bar widget (static HTML)
packages/
  core/             Shared UI, types, i18n, formatters
  db-pg/            Postgres client, queries, mutations
  db-sqlite/        SQLite client, queries, mutations
compose.yaml
```

## Development

```bash
# Web
make install && make dev
make test   lint   migrate   seed

# Desktop
cd apps/desktop && pnpm dev
```

## License

[AGPL-3.0](./LICENSE). Self-host, fork, modify, redistribute — any hosted derivative must publish its source.
