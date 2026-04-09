# Florin

> A self-hostable, open-source personal finance dashboard for European households.
> Links to your real bank via Enable Banking (PSD2), keeps your data on your own
> hardware, and looks like a modern YNAB / Copilot Money instead of 2005's GnuCash.

![Status](https://img.shields.io/badge/status-phase%201-blue)
![License](https://img.shields.io/badge/license-AGPL--3.0-green)
![Stack](https://img.shields.io/badge/stack-Next.js%2015%20%C2%B7%20Postgres%2016%20%C2%B7%20Drizzle-111)

---

## Why Florin?

Most personal finance apps either (a) cost a monthly subscription and want to
sell your transactions, or (b) are aging desktop tools. Florin's opinionated
take:

- **Self-hosted.** One `docker compose up`. Your data lives on your machine or
  a box you own. No third-party aggregation service sees your ledger.
- **European-first.** Bank linking goes through [Enable Banking](https://enablebanking.com/),
  a PSD2 aggregator covering 2 000+ EU banks (Boursorama, La Banque Postale,
  Revolut, N26, Fortuneo, Crédit Agricole, Caixa, Deutsche Bank, …). You
  register your own free app and keep the credentials.
- **Single-tenant.** One admin, one instance — simpler auth, simpler model,
  zero risk of cross-user data leaks. Want to share with a partner or friend?
  Each of you runs your own copy; no shared database, no invite flow to worry
  about.
- **YNAB-style workflow.** Group categories by intention (Needs / Wants / Bills
  / Savings / Income), review new imports before they hit your stats, and
  recategorize in bulk.
- **Built for real use, not screenshots.** Dashboard, review queue, bulk
  actions, mobile-friendly layout, PWA-installable, proper light/dark mode.

---

## Features (Phase 1)

- Multi-account tracking: checking, savings, cash, loans, brokerage
- Manual transaction entry + inline category editing
- YNAB-style category hierarchy with auto-categorization rules
- Dashboard: net worth, burn rate (clickable to drill in), safety gauge, 12-month
  patrimony chart with smoothed EWMA trend and forecast, category pie, top
  expenses
- Review queue for bank-imported transactions (approve / recategorize / delete
  in bulk)
- One-shot legacy XLSX importer (for the classic YNAB-style spreadsheet with
  a `Cleared` UUID column per row)
- Resizable + reorderable transactions table with persisted column widths
- Mobile: stacked card layout for the review queue, PWA installable on iOS /
  Android
- Single `docker compose up`
- AGPL-3.0 license

## Roadmap

| Phase | Scope | Status |
|-------|-------|--------|
| 1 | Foundation, manual entry, legacy import, dashboard | ✅ shipped |
| 2 | Enable Banking integration (PSD2 bank linking, auto-sync) | 🚧 in progress |
| 3 | Trade Republic via `pytr` (Python sidecar) | planned |
| 4 | Loans with amortization schedule + divergence detection | planned |
| 5 | Production recipes (Tailscale Serve, Caddy, CI backups) | planned |
| 6 | i18n, full offline PWA, advanced filters, observability | planned |

---

## Requirements

- **Docker** + **Docker Compose** v2 (only hard requirement for running)
- **pnpm** + **Node 20+** (only if you want to develop or run one-shot scripts
  like the legacy importer and password hasher)
- ~200 MB disk for the Postgres volume + a few dozen MB for the app image
- A **free Enable Banking developer app** if you want to link real bank
  accounts (skip this if you'll type transactions by hand or only import
  spreadsheets)

---

## Quickstart

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
> doesn't try to expand them as shell variables:
>
> ```bash
> ADMIN_PASSWORD_HASH=\$2b\$12\$...
> ```

### 4. Start the stack

```bash
cd ..            # back to the repo root
docker compose up -d
```

Wait ~30 seconds for the web container to pass its health check. The Postgres
container is deliberately mapped to host port **5433** (not 5432) so it
doesn't clash with any system Postgres. Inside the compose network the app
still talks to it on 5432.

### 5. Run migrations and seed default categories

```bash
cd apps/web
pnpm drizzle-kit migrate
pnpm tsx src/db/seed.ts
```

### 6. Open the app

Visit `http://localhost:3000`, sign in with your email + the password you
hashed in step 3, and start adding accounts.

---

## Linking a real bank account (Enable Banking)

Florin uses [Enable Banking](https://enablebanking.com/) as its PSD2 gateway.
The sandbox is free; production access is free for personal use up to their
listed limits.

1. **Register a free developer account** at <https://enablebanking.com/>.
2. **Create an application** in the [control panel](https://enablebanking.com/cp/applications).
   Name it whatever you like (e.g. "Florin Personal").
3. **Generate an RSA key pair** the app will use to sign requests:

   ```bash
   openssl genrsa -out enablebanking-private.pem 2048
   openssl rsa -in enablebanking-private.pem -pubout -out enablebanking-public.pem
   ```

4. **Upload the public key** (`enablebanking-public.pem`) to your app in the
   Enable Banking control panel. Keep the private key somewhere safe on the
   host running Florin — **do not commit it**.
5. **Set the redirect URL** in the control panel to match your Florin
   deployment, e.g. `https://florin.mydomain.tld/api/banking/callback` for a
   remote server, or `http://localhost:3000/api/banking/callback` for local
   development.
6. **Fill in `.env`:**

   ```bash
   ENABLE_BANKING_APP_ID=<your-application-id>
   ENABLE_BANKING_PRIVATE_KEY_PATH=/path/to/enablebanking-private.pem
   ENABLE_BANKING_REDIRECT_URL=https://florin.mydomain.tld/api/banking/callback
   ```

7. `docker compose restart web` to pick up the new env vars.
8. In Florin → Accounts → "Link bank", pick your institution, follow the
   PSD2 SCA flow on your bank's website, and confirm. New transactions
   will land in the Review queue.

> If you leave the three `ENABLE_BANKING_*` env vars blank, Florin runs in
> **manual-only** mode: type transactions yourself, or import from the legacy
> XLSX importer.

---

## Importing existing data

### Legacy YNAB-style XLSX

If you kept your finances in an old YNAB-style spreadsheet (the one with a
`Cleared` UUID column per row), Florin ships a one-shot importer that is
**idempotent** — you can re-run it safely, it dedupes on the UUID.

From `apps/web/`:

```bash
node --env-file=.env --import tsx scripts/import-legacy-xlsx.ts /path/to/finances.xlsx
```

Or from the repo root:

```bash
make import-legacy FILE=/path/to/finances.xlsx
```

It will:

- Upsert accounts
- Insert new transactions (skipping rows that already exist by UUID)
- Backfill categories on previously-imported uncategorized rows
- Recompute account balances

### YNAB CSV export

Not yet — this is a known gap. If you're migrating from YNAB and want a
drop-in path, open an issue and describe your export format. Until then the
workaround is to reshape your CSV into the legacy XLSX format, or to type
manual transactions.

---

## Backups

One-liner to snapshot the database into a gzipped SQL dump:

```bash
mkdir -p backups
docker exec florin-db pg_dump -U florin -d florin --no-owner --no-privileges \
  | gzip -9 > "backups/florin-$(date -u +%Y%m%dT%H%M%SZ).sql.gz"
```

To restore:

```bash
gunzip -c backups/florin-<TIMESTAMP>.sql.gz \
  | docker exec -i florin-db psql -U florin -d florin
```

You'll probably want to stick the first snippet in a nightly cron on whichever
host runs the stack.

---

## Self-hosting on a remote server

Florin is a boring Next.js + Postgres stack, so anything that runs Docker
Compose runs Florin. A few tested setups:

- **Proxmox LXC**: create a Debian 12 unprivileged container with nesting
  enabled, install Docker + Compose, clone the repo, follow the quickstart.
- **Bare VPS**: any Ubuntu / Debian box, same recipe.
- **Synology / UGREEN NAS**: use their container manager. Map host port 3000
  to the web service, keep port 5433 bound to 127.0.0.1.

**Do not expose Florin to the public internet without a reverse proxy.** The
container binds to `127.0.0.1:3000` on purpose. Put Caddy / Traefik / nginx /
Tailscale Serve in front of it with TLS and basic HTTP auth as a second layer
if you want to be paranoid.

### Bringing over existing data

A fresh server means a fresh database. Two ways to populate it:

1. **Re-run the legacy XLSX importer** on the server (same command as above),
   pointing at a copy of your spreadsheet.
2. **Restore a pg_dump backup** from your old machine:

   ```bash
   # on the old machine
   docker exec florin-db pg_dump -U florin -d florin --no-owner --no-privileges \
     | gzip -9 > florin.sql.gz
   scp florin.sql.gz user@server:/tmp/

   # on the server, after the stack is up and migrations have run once
   gunzip -c /tmp/florin.sql.gz \
     | docker exec -i florin-db psql -U florin -d florin
   ```

---

## Updating

### On the host running Florin

```bash
cd florin
git pull
docker compose up -d --build web
cd apps/web
pnpm drizzle-kit migrate   # only if there are new files under apps/web/drizzle/
```

`--build web` rebuilds just the web image, keeps Postgres running, and incurs
no data loss.

### Remote one-liner (from your dev machine)

If your deployment host is reachable over SSH, you can ship the current `main`
in one command from the repo root:

```bash
make deploy
```

This pushes `main`, then SSHes into the deployment host and runs the rebuild
for you. Configure it once via environment variables (put them in your shell
profile, or in a git-ignored `.envrc` if you use direnv):

```bash
export FLORIN_DEPLOY_HOST=myserver          # ssh target (alias or user@host)
export FLORIN_DEPLOY_PATH=/opt/florin       # path to the florin repo on the host
# Optional — wrap the remote command (e.g. `pct exec 100 --` for Proxmox LXC):
export FLORIN_DEPLOY_WRAP=""
```

Requirements: key-based SSH to `FLORIN_DEPLOY_HOST`, and `docker compose` on
the target. Run `make deploy-status` afterwards to poll the health endpoint.

---

## Troubleshooting

- **`DATABASE_URL: invalid input`** when running a script: make sure you invoke
  it as `node --env-file=.env --import tsx scripts/import-legacy-xlsx.ts <file>`
  from `apps/web/`, not via `pnpm tsx`. The envfile flag is what loads `.env`.
- **Can't sign in**: check that you escaped every `$` in `ADMIN_PASSWORD_HASH`
  with `\$` in `.env`, otherwise Compose eats them. Restart the web container
  after fixing.
- **Port 5433 already in use**: you have a local Postgres on 5433. Either stop
  it, or change the host-side mapping in `compose.yaml` (the internal 5432 is
  fine to keep).
- **Bank link stuck**: the Enable Banking sandbox is flaky on weekends — try
  again, or switch to a real institution. Double-check the redirect URL in
  the control panel matches your `ENABLE_BANKING_REDIRECT_URL`.

---

## Repository layout

```
florin/
├── apps/web/              # Next.js 15 + Drizzle + Postgres
│   ├── src/
│   ├── scripts/           # hash-password, import-legacy-xlsx, peek-xlsx
│   └── drizzle/           # migrations
├── backups/               # gitignored — pg_dump output goes here
├── docs/                  # design specs & implementation notes
├── compose.yaml           # db + web
├── Makefile               # convenience targets
└── .env.example
```

## Development

```bash
make install   # pnpm install in apps/web
make dev       # next dev
make test      # vitest run
make lint      # biome check
make format    # biome format --write
make migrate   # drizzle-kit migrate
make seed      # seed default categories
```

---

## License

[AGPL-3.0](./LICENSE) — copyleft. You can self-host, fork, modify, and
redistribute, but any hosted derivative (even a SaaS) must publish its
modified source. This is intentional: Florin is built so personal finance
tooling stays in the commons.
