# Florin

> A self-hostable, open-source personal finance dashboard for European households.
> Available as a **web app** (Docker, Postgres) and a **native macOS desktop app**
> (Electron, SQLite). Links to your real bank via Enable Banking (PSD2), keeps
> your data on your own hardware, and looks like a modern YNAB / Copilot Money.

![Status](https://img.shields.io/badge/status-phase%202-blue)
![License](https://img.shields.io/badge/license-AGPL--3.0-green)
![Stack](https://img.shields.io/badge/stack-Next.js%2015%20%C2%B7%20Electron%2035%20%C2%B7%20Drizzle-111)

---

## Why Florin?

Most personal finance apps either (a) cost a monthly subscription and want to
sell your transactions, or (b) are aging desktop tools. Florin's opinionated
take:

- **Self-hosted.** One `docker compose up` (web) or a single `.dmg` (desktop).
  Your data lives on your machine or a box you own. No third-party aggregation
  service sees your ledger.
- **European-first.** Bank linking goes through [Enable Banking](https://enablebanking.com/),
  a PSD2 aggregator covering 2 000+ EU banks (Boursorama, La Banque Postale,
  Revolut, N26, Fortuneo, Crédit Agricole, Caixa, Deutsche Bank, …). You
  register your own free app and keep the credentials.
- **Single-tenant.** One admin, one instance — simpler auth, simpler model,
  zero risk of cross-user data leaks.
- **YNAB-style workflow.** Group categories by intention (Needs / Wants / Bills
  / Savings / Income), review new imports before they hit your stats, and
  recategorize in bulk.
- **Two deployment models.** Web app with Postgres for servers, native Electron
  desktop app with SQLite for zero-config local use.

---

## Features

### Core
- Multi-account tracking: checking, savings, cash, loans, brokerage
- Manual transaction entry + inline category editing
- YNAB-style category hierarchy with auto-categorization rules
- Dashboard: net worth, burn rate, safety gauge, monthly margin (auto-detected
  salary), 12-month patrimony chart with EWMA trend and forecast, category pie,
  top expenses
- Review queue for bank-imported transactions (approve / recategorize / delete
  in bulk)
- Reflect analytics: 52-week GitHub-style spending heatmap (click a day to
  jump to its transactions, filter out categories like rent), rolling savings
  rate (3/6/12 mo), subscriptions radar, "if I stopped X" counterfactual
  savings explorer, income vs spending, net worth over time, category breakdown
- CSV / OFX / QFX drag-and-drop import for bank statements
- PDF monthly summary export
- Keyboard shortcuts (Cmd+K search, Cmd+N new transaction, Cmd+, settings)
- Dark / light mode, i18n (English, French)
- AGPL-3.0 license

### Web App (`apps/web`)
- Docker Compose one-liner deployment (Next.js 15 + Postgres 16)
- NextAuth single-admin authentication
- Legacy YNAB-style XLSX idempotent importer
- PWA-installable on iOS / Android
- Mobile-friendly layout with stacked card review queue

### Desktop App (`apps/desktop`)
- Native macOS app (Electron 35 + Next.js 15 + SQLite)
- Zero-config: all data stored locally in `~/Library/Application Support/Florin/florin.db`
- Menu bar tray widget with net worth, burn rate, recent transactions
- PIN lock screen with scrypt-hashed storage
- Onboarding wizard (locale, categories, first account, banking setup)
- Auto-updater via GitHub Releases
- No server, no cloud, no telemetry

---

## Roadmap

| Phase | Scope | Status |
|-------|-------|--------|
| 1 | Foundation, manual entry, legacy import, dashboard | ✅ shipped |
| 2 | Enable Banking (PSD2), desktop app, CSV/OFX import | ✅ shipped |
| 3 | Trade Republic via `pytr` (Python sidecar) | planned |
| 4 | Multi-currency display with live exchange rates | planned |
| 5 | Production recipes (Tailscale Serve, Caddy, CI backups) | planned |

---

## Quickstart — Desktop App (macOS)

Download the latest `.dmg` from [Releases](https://github.com/adrbn/florin/releases),
drag Florin to Applications, and launch. The onboarding wizard walks you through
language, categories, and your first account.

**Development:**

```bash
cd apps/desktop
pnpm install
pnpm dev          # builds Electron main process, launches app
```

---

## Quickstart — Web App (Docker)

### 1. Clone and configure

```bash
git clone https://github.com/adrbn/florin.git
cd florin
cp .env.example .env
```

### 2. Generate secrets

```bash
openssl rand -base64 32   # → paste into DB_PASSWORD
openssl rand -base64 32   # → paste into NEXTAUTH_SECRET
```

Edit `.env`:

```bash
DB_PASSWORD=<paste-1>
NEXTAUTH_SECRET=<paste-2>
ADMIN_EMAIL=you@example.com
```

### 3. Hash your admin password

```bash
cd apps/web
pnpm install
pnpm tsx scripts/hash-password.ts "your-strong-password"
```

Copy the bcrypt hash into `.env` as `ADMIN_PASSWORD_HASH`.

> **Important:** escape every `$` in the hash with `\$` so Docker Compose
> doesn't try to expand them as shell variables.

### 4. Start the stack

```bash
cd ..            # back to the repo root
docker compose up -d
```

### 5. Run migrations and seed

```bash
cd apps/web
pnpm drizzle-kit migrate
pnpm tsx src/db/seed.ts
```

### 6. Open the app

Visit `http://localhost:3000`, sign in with your email + password, and start
adding accounts.

---

## Linking a Real Bank Account (Enable Banking)

Florin uses [Enable Banking](https://enablebanking.com/) as its PSD2 gateway.
The sandbox is free; production access is free for personal use.

1. Register at <https://enablebanking.com/> and create an application.
2. Generate an RSA key pair:
   ```bash
   openssl genrsa -out enablebanking-private.pem 2048
   openssl rsa -in enablebanking-private.pem -pubout -out enablebanking-public.pem
   ```
3. Upload the public key to the Enable Banking control panel.
4. **Add the redirect URI** for your deployment in the Enable Banking app settings:
   - **Desktop:** `https://127.0.0.1:3847/api/banking/callback`
   - **Web (self-hosted):** `https://florin.yourdomain.tld/api/banking/callback`
5. Configure credentials:
   - **Desktop:** go to Settings > Bank Sync, enter your App ID, and click
     "Import .pem file..." to securely import your private key. The key is
     copied into `~/Library/Application Support/Florin/` and never leaves
     your machine.
   - **Web:** fill in `.env`:
     ```bash
     ENABLE_BANKING_APP_ID=<your-application-id>
     ENABLE_BANKING_PRIVATE_KEY_PATH=/path/to/enablebanking-private.pem
     ENABLE_BANKING_REDIRECT_URL=https://florin.yourdomain.tld/api/banking/callback
     ```

---

## Importing Data

### CSV / OFX / QFX (Desktop & Web)

Navigate to an account's detail page and drag-and-drop your bank statement file
onto the import zone. Florin auto-detects column mapping (date, payee, amount,
debit/credit) and supports European date and number formats.

### Legacy YNAB-style XLSX (Web only)

```bash
cd apps/web
node --env-file=.env --import tsx scripts/import-legacy-xlsx.ts /path/to/finances.xlsx
```

Idempotent — safe to re-run. Dedupes on UUID.

---

## Backups

### Web (Postgres)

```bash
docker exec florin-db pg_dump -U florin -d florin --no-owner --no-privileges \
  | gzip -9 > "backups/florin-$(date -u +%Y%m%dT%H%M%SZ).sql.gz"
```

### Desktop (SQLite)

Copy `~/Library/Application Support/Florin/florin.db` — it's a single file.
The app also offers a JSON export under Settings → Data.

---

## Repository Layout

```
florin/
├── apps/
│   ├── web/                 # Next.js 15 + Drizzle + Postgres (Docker)
│   │   ├── src/
│   │   ├── scripts/         # hash-password, import-legacy-xlsx
│   │   └── drizzle/         # migrations
│   └── desktop/             # Electron 35 + Next.js 15 + SQLite
│       ├── main/            # Electron main process (TS → esbuild → CJS)
│       ├── src/             # Next.js app (pages, components, server actions)
│       ├── tray-ui/         # Menu bar widget (static HTML)
│       └── assets/          # Tray icons
├── packages/
│   ├── core/                # Shared UI components, types, i18n, formatters
│   ├── db-pg/               # PostgreSQL client, queries, mutations (web)
│   └── db-sqlite/           # SQLite client, queries, mutations (desktop)
├── compose.yaml             # Web: db + web services
├── Makefile                 # Convenience targets
└── .env.example
```

## Development

```bash
# Web app
make install   # pnpm install
make dev       # next dev
make test      # vitest run
make lint      # biome check
make migrate   # drizzle-kit migrate
make seed      # seed default categories

# Desktop app
cd apps/desktop
pnpm dev       # esbuild main + electron .
```

---

## Self-hosting on a Remote Server

Florin is a boring Next.js + Postgres stack, so anything that runs Docker
Compose runs Florin. Tested setups: Proxmox LXC, bare VPS, Synology / UGREEN
NAS.

**Do not expose Florin to the public internet without a reverse proxy.** Put
Caddy / Traefik / nginx / Tailscale Serve in front with TLS.

### Remote deploy (one-liner)

```bash
make deploy
```

Configure via env vars: `FLORIN_DEPLOY_HOST`, `FLORIN_DEPLOY_PATH`,
`FLORIN_DEPLOY_WRAP`.

---

## License

[AGPL-3.0](./LICENSE) — copyleft. You can self-host, fork, modify, and
redistribute, but any hosted derivative must publish its modified source.
