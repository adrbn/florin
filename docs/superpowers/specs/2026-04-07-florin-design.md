# Florin — Design Spec (v1.0 MVP)

**Status:** Draft for review
**Date:** 2026-04-07
**Author:** Adrien (with Claude as design partner)

---

## 1. Vision & scope

**Florin** est un dashboard de finances personnelles **self-hostable, open source, et joli** pour les particuliers européens. Il agrège les comptes bancaires (via Open Banking PSD2 / Enable Banking), un courtier (Trade Republic via `pytr`), et des comptes manuels — et fournit un suivi de patrimoine, des dépenses catégorisées, et un suivi de prêts avec échéancier calculé.

**Modèle de distribution** : open source (AGPL-3.0), single-user-per-instance, déployable en `docker compose up`. Chaque utilisateur fournit ses propres credentials Enable Banking / Trade Republic. Aucun service hébergé multi-tenant — le projet n'est pas un AISP.

**Public cible secondaire** : ex-utilisateurs de YNAB / Mint / Linxo / Bankin' qui veulent reprendre le contrôle de leurs données et n'ont pas envie de payer un abonnement mensuel.

### 1.1 Objectifs

1. **Auto-sync quotidien** des comptes bancaires (LBP en MVP, plus tard d'autres) et de Trade Republic.
2. **Classification automatique** des transactions par règles regex sur le libellé.
3. **Vue agrégée** du patrimoine net et brut, courbe d'évolution sur 12 mois.
4. **Calcul d'échéancier de prêts** complet, avec détection de divergence vs solde réel synchronisé.
5. **Workflow de re-consentement DSP2** clair, avec compte à rebours visible 30 jours avant expiration.
6. **Esthétique soignée** — cohérence visuelle au niveau des produits SaaS modernes (Linear, Notion, Vercel Analytics).
7. **Installation en moins de 15 minutes** pour un développeur qui clone le repo.

### 1.2 Non-objectifs (explicitement hors v1.0)

- Multi-utilisateurs dans une seule instance.
- Multi-devises actives (EUR uniquement, schéma préparé pour FX en v2).
- Application mobile native (la PWA fait le travail).
- Service hébergé multi-tenant (illégal sans agrément AISP).
- Tracking historique des cours d'actions pour le portefeuille (Ghostfolio existe pour ça).
- Splits de transactions, transactions récurrentes (hors prêts), goals d'épargne, exports comptables, IA de catégorisation.
- Notifications push / email automatiques (logging UI uniquement en v1.0).
- Connecteurs autres que LBP via Enable Banking (l'archi est pluggable, mais on ne livre que LBP en MVP).

### 1.3 Critères de succès du MVP

- ✅ L'auteur (Adrien) remplace son Google Sheets par Florin et l'utilise quotidiennement pendant 30 jours sans frustration.
- ✅ Une autre personne arrive à `git clone && docker compose up && naviguer vers https://...` et a un dashboard fonctionnel sur ses propres données en moins de 15 minutes.
- ✅ La sync quotidienne tourne 14 jours d'affilée sans intervention manuelle (modulo le re-consent DSP2 sur ce cycle).
- ✅ Repo public sur GitHub avec README en anglais, license AGPLv3, GitHub Actions vert.

---

## 2. Architecture haut niveau

```
        ┌─────────────────────────────────────┐
        │  Browser / iOS PWA                  │
        └───────────────┬─────────────────────┘
                        │ HTTPS
                        ▼
            finances.<tailnet>.ts.net
            (ou finance.example.com via Caddy)
                        │
        ┌───────────────▼───────────────┐
        │  Asgard (Proxmox LXC)         │
        │                               │
        │  ┌─────────────────────────┐  │
        │  │ Tailscale Serve / Caddy │  │
        │  └────────────┬────────────┘  │
        │               │               │
        │  ┌────────────▼────────────┐  │
        │  │ apps/web (Next.js 15)   │  │
        │  │  • UI + Server Actions  │  │
        │  │  • Auth.js v5           │  │
        │  │  • Enable Banking REST  │  │
        │  │  • Loan amortization    │  │
        │  │  • In-process scheduler │  │
        │  │    (instrumentation.ts) │  │
        │  └────────────┬────────────┘  │
        │               │               │
        │  ┌────────────▼────────────┐  │
        │  │ Postgres 16             │  │
        │  └────────────▲────────────┘  │
        │               │               │
        │  ┌────────────┴────────────┐  │
        │  │ apps/tr-sync (Python)   │  │
        │  │  • pytr daemon          │  │
        │  │  • APScheduler          │  │
        │  │  • sync_jobs poller     │  │
        │  └─────────────────────────┘  │
        └───────────────────────────────┘
```

**Trois conteneurs Docker** : `db` (Postgres), `web` (Next.js), `tr-sync` (Python). Pas de Redis, pas de RabbitMQ, pas de NGINX externe. Reverse proxy = Tailscale Serve (préférence) ou Caddy (alternative).

**Communication TS ↔ Python** : exclusivement via Postgres (table `sync_jobs` + `worker_status`). Aucune API HTTP exposée par le worker Python. Surface d'attaque côté Python = nulle.

---

## 3. Modèle de données

15 tables Postgres, schéma owné par Drizzle ORM (côté TS). Le worker Python lit/écrit en SQL pur via SQLAlchemy Core (pas d'ORM Python — pas de duplication de modèles).

### 3.1 Liste des tables

| Table | Cardinalité | Rôle |
|---|---|---|
| `users` | 1 row | Single user de l'instance, NextAuth-compatible |
| `accounts` | N | Tout container financier (CCP, livret, prêt, broker, cash, manuel) |
| `transactions` | N×N | **Source de vérité unique** — toutes les opérations |
| `category_groups` | ~5 | Bills / Needs / Wants / Savings / Revenus |
| `categories` | ~20 | Feuilles avec emoji + drapeau `is_fixed` |
| `categorization_rules` | N | Auto-cat par regex sur `payee` + bornes de montant |
| `balance_snapshots` | N×jour | Série temporelle du solde par compte (1 ligne/jour/compte) |
| `loans` | 1:1 avec compte | Métadonnées prêt (capital, taux, durée, mensualité) + flag `is_diverged` + `last_diverged_at` + `last_divergence_amount` pour la détection d'écart vs solde réel |
| `loan_schedule_entries` | ~60 par prêt | Échéancier généré localement par calcul |
| `portfolio_holdings` | N | Positions Trade Republic |
| `enable_banking_sessions` | N | Suivi des consents DSP2 (session_id, valid_until) |
| `tr_credentials` | 1 row | PIN TR chiffré AES-GCM |
| `sync_jobs` | N | File de jobs Next.js → Python worker |
| `worker_status` | 1 row | Heartbeat 30s du worker |
| `app_settings` | N k/v | Config runtime modifiable depuis l'UI |

### 3.2 Choix structurants

- **Montants signés** : `transactions.amount numeric(14,2)` — positif = inflow, négatif = outflow. Pas de colonnes séparées `inflow`/`outflow` (elles sont la source de la moitié des bugs YNAB-like).
- **Idempotence triple-clé** : dedup via `(source, external_id)` UNIQUE quand disponible, fallback `legacy_id` (UUID YNAB importé), fallback heuristique `(account_id, occurred_at, amount, normalized_payee)`.
- **`raw_data jsonb`** sur les transactions importées : payload brut du provider, pour debug et replay sans re-fetch.
- **Soft-delete** : `transactions.deleted_at timestamptz` + index partial. Toutes les queries filtrent.
- **Virements internes** : `transactions.transfer_pair_id uuid` — auto-détecté pour les patterns `VIREMENT/VRT INTERNE` avec montant miroir dans les 48h. Toutes les agrégations de dépenses excluent `transfer_pair_id IS NOT NULL`.
- **Échéancier prêt matérialisé** (pas calculé à la volée) : ~60 lignes par prêt, gain de simplicité côté queries de visualisation.
- **Balances dénormalisées** : `accounts.current_balance` mis à jour à chaque sync, avec test d'intégrité périodique vs `SUM(transactions.amount)`.

Le schéma Drizzle complet vit dans `apps/web/src/db/schema.ts` une fois implémenté. Les noms de colonnes seront partagés au worker Python via un fichier généré `apps/tr-sync/tr_sync/_schema.py` (script de build qui parse le schéma Drizzle).

---

## 4. Stack technique

### 4.1 TypeScript (apps/web)

| Couche | Choix |
|---|---|
| Runtime | Node 22 LTS |
| Framework | Next.js 15 (App Router, RSC, Server Actions) |
| Langage | TypeScript strict |
| ORM | Drizzle ORM |
| DB driver | `postgres` (porsager) |
| Auth | Auth.js v5 credentials provider |
| UI primitives | shadcn/ui + Radix + Tailwind v4 |
| Charts | shadcn/ui charts (Recharts wrapped) |
| Tables | TanStack Table v8 |
| Forms | React Hook Form + Zod resolver |
| Validation | Zod (forms, server actions, env vars) |
| Dates | date-fns |
| i18n | next-intl (EN base, FR additional) |
| Lint+format | Biome |
| Tests | Vitest (unit), Playwright (E2E), testcontainers (integration) |
| Package mgr | pnpm |

### 4.2 Python (apps/tr-sync)

| Couche | Choix |
|---|---|
| Runtime | Python 3.12 |
| Package mgr | uv |
| TR client | pytr |
| Scheduler | APScheduler |
| DB | psycopg v3 (sync) + SQLAlchemy Core |
| Crypto | `cryptography` (AES-GCM) |
| Config | pydantic-settings |
| Logging | structlog |
| Tests | pytest |

### 4.3 Build / CI / déploiement

- Conteneurs Docker multi-stage pour `web` et `tr-sync`
- `compose.yaml` (base) + overlays `compose.tailscale.yaml` / `compose.caddy.yaml`
- GitHub Actions : typecheck + lint + tests sur PR, build & push images sur tag → GHCR
- Husky + lint-staged pour pre-commit
- Makefile racine : `make test`, `make lint`, `make build`, `make up`, `make import-legacy`

### 4.4 Structure du repo

```
florin/
├── README.md                        # EN
├── LICENSE                          # AGPL-3.0
├── CONTRIBUTING.md
├── .env.example
├── compose.yaml
├── compose.tailscale.yaml
├── compose.caddy.yaml
├── Makefile
├── docs/
│   ├── architecture.md
│   ├── deployment-tailscale.md
│   ├── deployment-caddy.md
│   ├── enable-banking-setup.md
│   ├── trade-republic-setup.md
│   ├── re-consent.md
│   ├── data-model.md
│   └── superpowers/specs/           ← ce doc
├── apps/
│   ├── web/
│   │   ├── src/
│   │   │   ├── app/                 # App Router
│   │   │   │   ├── (auth)/login/
│   │   │   │   ├── (dashboard)/
│   │   │   │   │   ├── page.tsx
│   │   │   │   │   ├── transactions/
│   │   │   │   │   ├── accounts/
│   │   │   │   │   ├── loans/
│   │   │   │   │   ├── portfolio/
│   │   │   │   │   ├── categories/
│   │   │   │   │   └── settings/
│   │   │   │   ├── api/
│   │   │   │   │   ├── auth/[...nextauth]/
│   │   │   │   │   ├── enable-banking/callback/
│   │   │   │   │   └── health/
│   │   │   │   └── layout.tsx
│   │   │   ├── components/
│   │   │   │   ├── ui/              # shadcn primitives
│   │   │   │   ├── dashboard/
│   │   │   │   ├── transactions/
│   │   │   │   ├── accounts/
│   │   │   │   ├── loans/
│   │   │   │   └── shared/
│   │   │   ├── server/
│   │   │   │   ├── actions/
│   │   │   │   ├── queries/
│   │   │   │   ├── auth.ts
│   │   │   │   ├── env.ts
│   │   │   │   └── instrumentation.ts  # in-process scheduler
│   │   │   ├── lib/
│   │   │   │   ├── enable-banking/
│   │   │   │   ├── loans/
│   │   │   │   ├── categorization/
│   │   │   │   ├── transfers/
│   │   │   │   ├── crypto/
│   │   │   │   └── utils/
│   │   │   ├── db/
│   │   │   │   ├── schema.ts        # Drizzle, source of truth
│   │   │   │   ├── client.ts
│   │   │   │   └── seed.ts
│   │   │   └── i18n/
│   │   │       ├── messages/{en,fr}.json
│   │   │       └── config.ts
│   │   ├── drizzle/                 # migrations
│   │   ├── public/manifest.webmanifest
│   │   ├── tests/{unit,e2e}/
│   │   ├── Dockerfile
│   │   ├── package.json
│   │   ├── biome.json
│   │   ├── drizzle.config.ts
│   │   ├── tailwind.config.ts
│   │   └── next.config.ts
│   └── tr-sync/
│       ├── src/tr_sync/
│       │   ├── __main__.py
│       │   ├── worker.py
│       │   ├── scheduler.py
│       │   ├── pytr_client.py
│       │   ├── jobs.py
│       │   ├── db.py
│       │   ├── crypto.py
│       │   ├── config.py
│       │   ├── heartbeat.py
│       │   └── _schema.py           # généré depuis Drizzle
│       ├── tests/
│       ├── Dockerfile
│       └── pyproject.toml
└── scripts/
    ├── import-legacy-xlsx.ts
    ├── reset-db.sh
    ├── generate-app-secret.sh
    └── sync-schema-to-python.ts     # parse Drizzle → écrit _schema.py
```

---

## 5. Flux de données critiques

### 5.1 Premier consentement Enable Banking (LBP)

1. User clique "Connecter LBP" dans `/settings/accounts`.
2. Server Action `initEnableBankingAuth`:
   - Génère un `state` aléatoire, INSERT dans `enable_banking_sessions` (status `pending`).
   - POST `https://api.enablebanking.com/auth` avec `{ aspsp: { name: 'La Banque Postale', country: 'FR' }, valid_until: now + 180d, redirect_url: ${PUBLIC_BASE_URL}/api/enable-banking/callback, psu_type: 'personal', state }`.
   - Retourne l'`auth_url` au client.
3. Client redirige vers `auth_url`.
4. User saisit son code 10 chiffres + mot de passe sur le site LBP.
5. LBP redirige vers `${PUBLIC_BASE_URL}/api/enable-banking/callback?code=Y&state=X`.
6. Route handler GET `callback`:
   - Vérifie `state` contre la DB → 404 si non trouvé ou expiré (>1h).
   - POST `https://api.enablebanking.com/sessions` avec `{ code }` → reçoit `{ session_id, accounts[] }`.
   - UPDATE `enable_banking_sessions` (status `active`, `authorized_at`, `valid_until = now + 180d`).
   - UPSERT chaque `account` dans `accounts` (kind = `checking|savings|loan` selon `cash_account_type`).
   - Pour chaque account, GET `/sessions/{id}/accounts/{aid}/transactions?date_from=now-90d` → INSERT dans `transactions` avec dedup `(source='enable_banking', external_id)`.
   - Run `categorize()` sur chaque nouvelle transaction.
   - INSERT `balance_snapshots` pour aujourd'hui.
   - Redirige vers `/accounts` avec un toast succès.

**Erreur** : si le user abandonne, le row `pending` est supprimé par un cleanup-cron toutes les heures.

### 5.2 Sync quotidien automatique

**Côté `web` (Next.js)** : `instrumentation.ts` démarre un scheduler in-process au boot.
- Cron `0 6 * * *` → fonction `runEnableBankingSync()`.
- Pour chaque `enable_banking_sessions` actif :
  - Pour chaque `account` lié, GET `transactions?date_from=last_synced_at`.
  - UPSERT dans `transactions` (idempotent via unique constraint).
  - UPDATE `accounts.current_balance` et `accounts.last_synced_at`.
  - Run `categorize()` sur les nouveaux.
  - INSERT `balance_snapshots` du jour.
  - Pour les comptes de prêt : compare `current_balance` vs `loan_schedule_entries[current_month].remaining_principal` → si écart > 1 €, UPDATE `loans.is_diverged = true`, `loans.last_diverged_at = now()`, `loans.last_divergence_amount = écart`.
- Update `worker_status['web-scheduler']` heartbeat.
- Si HTTP 401/403 sur EB : UPDATE session status `expired`, log warning, badge UI rouge.

**Côté `tr-sync` (Python)** : APScheduler in-process.
- Cron `5 6 * * *` → INSERT job `{ kind: 'tr_sync_full', status: 'pending', created_by: 'cron' }` dans `sync_jobs`.
- Boucle principale `worker.py` poll toutes les 5s :
  ```sql
  SELECT * FROM sync_jobs
  WHERE status = 'pending' AND kind LIKE 'tr_%'
  ORDER BY requested_at
  FOR UPDATE SKIP LOCKED
  LIMIT 1
  ```
- Si job trouvé : UPDATE `started_at`, `status = running`. Exécute `pytr_client.run_full_sync()` :
  - Login pytr (avec session persistée dans `/data/tr-session`).
  - Récupère portfolio holdings → UPSERT `portfolio_holdings`.
  - Récupère cash transactions → INSERT `transactions` avec `external_id` du timeline pytr.
  - Calcule la valorisation totale → UPDATE `accounts.current_balance` du compte broker.
  - INSERT `balance_snapshots`.
- UPDATE `finished_at`, `status = success` (ou `failed` + `error_message`).
- Heartbeat `worker_status['tr-sync']` toutes les 30s en thread séparé.

### 5.3 Ajout manuel d'une transaction

1. User ouvre modal "+ Transaction" depuis n'importe quelle page.
2. Form : compte (select), montant (signed), date, payee, catégorie (optionnel), memo.
3. Server Action `addTransaction`:
   - Zod validation.
   - INSERT dans `transactions` avec `source = 'manual'`.
   - Si pas de catégorie : `categorize()` automatique.
   - Recompute `accounts.current_balance`.
   - `revalidatePath('/dashboard', '/transactions')`.
4. Toast succès, modal close.

**Détection de doublon a posteriori** : à chaque sync EB, pour chaque nouvelle transaction, check s'il existe une transaction `manual` dans les 7 jours autour avec montant identique et payee similaire (Levenshtein < 3) → propose la fusion dans une UI dédiée (bannière "X transactions à confirmer").

### 5.4 Catégorisation automatique

```ts
async function categorize(txn: Transaction): Promise<UUID | null> {
  const rules = await db.query.categorizationRules.findMany({
    where: eq(categorizationRules.isActive, true),
    orderBy: desc(categorizationRules.priority),
  })
  for (const rule of rules) {
    if (rule.matchAccountId && rule.matchAccountId !== txn.accountId) continue
    if (rule.matchPayeeRegex && !new RegExp(rule.matchPayeeRegex, 'i').test(txn.payee)) continue
    if (rule.matchMinAmount != null && txn.amount > rule.matchMinAmount) continue
    if (rule.matchMaxAmount != null && txn.amount < rule.matchMaxAmount) continue
    await incrementHits(rule.id)
    return rule.categoryId
  }
  return null
}
```

Volontairement bête. Pas de OR, pas de NOT, pas de groupes. 95% des cas réels couverts.

### 5.5 Calcul d'échéancier de prêt

Saisie utilisateur : `initial_principal`, `interest_rate_annual`, `term_months`, `monthly_payment`, `first_installment_date`, `day_of_month`.

```ts
function generateSchedule(loan: LoanInput): LoanScheduleEntry[] {
  const monthlyRate = loan.interest_rate_annual / 12
  let remaining = loan.initial_principal
  const entries: LoanScheduleEntry[] = []
  for (let n = 1; n <= loan.term_months; n++) {
    const interest = remaining * monthlyRate
    const principal = loan.monthly_payment - interest
    remaining = remaining - principal
    entries.push({
      installmentNumber: n,
      dueDate: addMonths(loan.first_installment_date, n - 1),
      paymentAmount: loan.monthly_payment,
      principalAmount: principal,
      interestAmount: interest,
      remainingPrincipal: Math.max(0, remaining),
    })
  }
  return entries
}
```

Régénéré dès qu'un paramètre change, écrit en bulk dans `loan_schedule_entries` (transaction qui DELETE+INSERT atomique).

**Détection de divergence** : à chaque sync EB, le `remaining_principal` théorique de l'échéance courante est comparé au `current_balance` retourné par l'API. Si écart > 1€ → flag `is_diverged` sur le prêt + badge UI.

### 5.6 Import legacy XLSX

`pnpm tsx scripts/import-legacy-xlsx.ts <path-to-xlsx>`

1. Parse `ACTIFS` → upsert `accounts` par `name`.
2. Extrait les `category_group/category` distincts de `HISTORIQUE TRANSACTIONS` → upsert `category_groups` + `categories`.
3. Itère sur `HISTORIQUE TRANSACTIONS` :
   - Skip si `legacy_id` (= UUID `Cleared`) déjà présent.
   - Convertit `Outflow`/`Inflow` en `amount` signé (`Inflow - Outflow`).
   - INSERT avec `source = 'legacy_xlsx'`, `external_id = legacy_id`.
   - Map `Category` → `categories.id` via lookup.
4. Parse `SUIVI SOLDE` → INSERT `balance_snapshots` (account_id NULL = total agrégé).
5. Rapport final : N créés / M skippés / E erreurs.

Idempotent — relançable sans dégât.

### 5.7 Détection des virements internes

À chaque INSERT/sync de transaction :

```ts
async function maybeLinkTransfer(txn: Transaction) {
  if (txn.transferPairId) return
  if (!/VIREMENT|VRT|VIRT|INTERNE/i.test(txn.payee)) return

  const mirror = await db.query.transactions.findFirst({
    where: and(
      ne(transactions.accountId, txn.accountId),
      eq(transactions.amount, -txn.amount),
      between(transactions.occurredAt, addDays(txn.occurredAt, -2), addDays(txn.occurredAt, +2)),
      isNull(transactions.transferPairId),
    ),
  })
  if (mirror) {
    const pairId = randomUUID()
    await db.update(transactions).set({ transferPairId: pairId }).where(or(eq(transactions.id, txn.id), eq(transactions.id, mirror.id)))
  }
}
```

Toutes les agrégations de dépenses excluent `transfer_pair_id IS NOT NULL`.

---

## 6. Robustesse, tests, déploiement

### 6.1 Gestion d'erreurs

| Erreur | Détection | Action |
|---|---|---|
| Consent EB expiré (HTTP 401/403) | Réponse API | UPDATE `eb_sessions.status='expired'` + bannière rouge UI |
| Rate limit EB (HTTP 429) | Header `Retry-After` | Log warning, skip cycle, prochain cron |
| pytr 2FA expired | Exception spécifique | UPDATE `worker_status.last_error`, badge orange UI |
| pytr réseau / TR down | Exception générique | Log, conserve dernières données, badge orange |
| Postgres down | Connection refused | Healthcheck Docker → restart auto |
| Divergence prêt | Calcul post-sync | Flag `is_diverged`, badge UI sur le prêt |
| Doublon transaction | Unique constraint | Catch silencieux (comportement attendu) |
| Worker silencieux > 2 min | Heartbeat stale | Badge rouge sur dashboard |

### 6.2 Re-consent UX (DSP2 180j)

- **J-30** : bannière jaune discrète "Reconnexion LBP requise dans 30 jours"
- **J-7** : bannière orange persistante
- **J-0+** : bannière rouge "Sync arrêtée — Reconnecter maintenant"
- Bouton "Reconnecter" → relance le flux 5.1
- Compte à rebours visible en permanence dans `/settings/accounts`

### 6.3 Stratégie de tests

| Couche | Outil | Cible | Quoi |
|---|---|---|---|
| Unit TS | Vitest | >90% sur `lib/` | Amortissement, règles, virements, parsing legacy, normalize payee |
| Unit Python | pytest | >80% sur `tr_sync/` | Job poller, ingestion (mock pytr), heartbeat, crypto |
| Integration TS | Vitest + testcontainers Postgres | KPIs, queries Drizzle | Insertion + agrégations dashboard, idempotence |
| E2E | Playwright | Parcours critiques | Login → Dashboard → Add txn → Voir → Catégoriser |
| Cross-lang | pytest+vitest fixture | AES-GCM | Encrypt Python ↔ Decrypt TS et inverse |

**TDD strict** sur `lib/loans/`, `lib/categorization/`, `lib/transfers/`. Tests-après pour le reste.

### 6.4 Déploiement Docker Compose

3 services + 2 overlays :

**Base** (`compose.yaml`) :
- `db` : `postgres:16-alpine`, volume persistent, healthcheck pg_isready
- `web` : build `apps/web`, env vars de DB + secrets, expose 3000, healthcheck `/api/health`
- `tr-sync` : build `apps/tr-sync`, env vars + volume `/data/tr-session` pour la session pytr

**Tailscale** (`compose.tailscale.yaml`) :
- Service `tailscale` (`tailscale/tailscale:latest`), `network_mode: service:tailscale` pour `web`
- `serve.json` configure HTTPS sur `finance.<tailnet>.ts.net:443` → `http://127.0.0.1:3000`
- `AllowFunnel: true` → expose temporairement le callback EB à Internet (sécurisé par auth + state validation)

**Caddy** (`compose.caddy.yaml`) :
- Service `caddy:2-alpine`, ports 80/443
- `Caddyfile` minimal : 5 lignes pour Let's Encrypt automatique

### 6.5 Variables d'environnement (`.env.example`)

```bash
# Database
DB_PASSWORD=                    # required, generate with openssl rand -base64 32

# Auth
NEXTAUTH_SECRET=                # required, generate with openssl rand -base64 32
APP_SECRET_KEY=                 # required, 32 bytes b64, used for AES-GCM (PIN TR)

# Public URL
PUBLIC_BASE_URL=                # ex: https://finance.adrien.ts.net

# Enable Banking (free Personal tier)
ENABLE_BANKING_APP_ID=          # from enablebanking.com console
ENABLE_BANKING_PRIVATE_KEY=     # PEM, base64-encoded for env

# Trade Republic (only if you use TR)
TR_PHONE_NUMBER=                # +33...
TR_PIN=                         # 4 digits, encrypted at rest

# Tailscale (if using compose.tailscale.yaml)
TS_AUTHKEY=                     # ephemeral or reusable

# Optional
LOG_LEVEL=info                  # debug|info|warn|error
```

### 6.6 Backup & restore

**Quotidien (cron Asgard 03:00)** :
```bash
docker exec florin-db pg_dump -U finance finance | gzip | age -r $BACKUP_AGE_KEY > /backups/florin-$(date +%F).sql.gz.age
# rotation 30 jours, sync vers B2/NAS
```

**Snapshots Proxmox** : LXC entier, hebdo, 4 semaines de rétention.

**Restore** :
```bash
docker compose down
age -d -i $BACKUP_AGE_KEY < backup.sql.gz.age | gunzip | docker exec -i florin-db psql -U finance finance
docker compose up -d
```

### 6.7 Update / migration

```bash
git pull
docker compose pull
docker compose run --rm web pnpm drizzle-kit migrate
docker compose up -d
```

Migrations Drizzle = SQL pur, lisibles, reversibles si on ajoute manuellement les `down.sql`.

---

## 7. Scope MVP v1.0 — récap

### Inclus
- Auth single-user (Auth.js credentials)
- Connecteur LBP via Enable Banking (CCP, Livret A, LEP, prêt étudiant)
- Connecteur Trade Republic via pytr (cash + portfolio holdings + valorisation totale)
- Comptes manuels (cash, autres)
- Sync quotidien automatique (cron in-process Next.js + APScheduler Python)
- Bouton "Sync now" par compte
- Re-consent EB : compte à rebours visible (30/7/0 jours), pas de mail
- Transactions : liste paginée filtrable, recherche, édition manuelle, soft-delete
- Catégorisation : CRUD + règles regex sur payee + bornes de montant
- Quick-add modal "+ Transaction"
- Dashboard principal :
  - Patrimoine net + brut (delta vs M-1)
  - Burn rate mensuel
  - Jauge de sécurité (jours)
  - Camembert dépenses du mois en cours par catégorie
  - Courbe patrimoine 12 mois
  - Top 5 dépenses du mois
- Page Comptes : liste, statut, dernier sync, badge santé
- Page Prêts : détails + échéancier complet calculé + détection divergence
- Page Portfolio (TR) : holdings + valorisation
- Page Catégories : CRUD + règles
- Page Settings : env, credentials, re-consent
- Détection automatique des virements internes
- Import legacy XLSX (script one-shot, idempotent)
- Worker heartbeat + badge UI
- PWA installable iOS
- Docker Compose 3 services + 2 overlays
- Doc deployment (Tailscale + Caddy)
- README EN + LICENSE AGPLv3

### Reporté à v1.1+
- iOS Shortcut bridge (API publique POST /transaction)
- Notifications email/push
- Budgets prévisionnels (PREV. vs REEL)
- Heatmap dépenses hebdo + courbes par catégorie
- Détection d'abonnements automatique
- Goals d'épargne
- Catégorisation par IA / LLM
- Connecteurs supplémentaires (Boursorama, Crédit Mutuel, etc.)
- Plugin system formel
- Multi-devises actives
- Splits de transactions
- Transactions récurrentes (hors prêts)
- Tags
- Historique des cours pour le portfolio
- Export comptable / CSV
- Audit log
- Dashboard 2FA TOTP

---

## 8. Risques résiduels & questions ouvertes

| # | Risque | Mitigation prévue | Décision |
|---|---|---|---|
| 1 | pytr peut casser à tout moment | Plan B = import PDF mensuel manuel | Accepté |
| 2 | DSP2 180j : friction utilisateur 2×/an | UX claire avec compte à rebours | Accepté |
| 3 | Tailscale Funnel expose `/login` à Internet pour le callback EB | Auth NextAuth + state validation | Accepté, à documenter |
| 4 | Drizzle moins mainstream que Prisma | Drizzle a >25k stars, en croissance | Accepté |
| 5 | Drift entre schéma Drizzle et constants Python | Script de génération `_schema.py` au build | À implémenter |
| 6 | Backup non chiffré par défaut | Script `scripts/backup.sh` chiffre via `age` par défaut | À implémenter |
| 7 | `instrumentation.ts` cron requires always-warm Next.js | Mode `next start` (pas serverless), healthcheck Docker | Documenté |
| 8 | Échéancier prêt nécessite saisie manuelle initiale | Wizard 4 champs, valeurs par défaut | Accepté |
| 9 | LBP n'expose probablement pas l'échéancier détaillé via PSD2 | Calcul local + détection divergence | Décidé en design |
| 10 | Détection virements internes = faux positifs possibles | Filtre regex `VIREMENT/VRT` strict | Accepté |
| 11 | Le format legacy XLSX est spécifique à Adrien | v1.0 supporte exactement son format, généralisation YNAB en v1.1 | Accepté |
| 12 | Pas de monitoring proactif | Webhook ntfy.sh / Healthchecks.io en v1.1 | Accepté |

### Questions ouvertes (non bloquantes)
- Faut-il une page de "Reports" agrégés (mois par mois, année par année) en v1.0 ou tout en widgets dashboard ? **Décision provisoire** : tout sur le dashboard en v1.0, page Reports en v1.1.
- Faut-il supporter les comptes en lecture seule (par ex. compte du conjoint) ? **Décision provisoire** : non, hors scope single-user.

---

## 9. Glossaire

| Terme | Définition |
|---|---|
| **AISP** | Account Information Service Provider — statut réglementaire DSP2 nécessaire pour héberger des credentials bancaires de tiers. **Florin n'est pas AISP**, chaque utilisateur héberge ses propres credentials. |
| **APScheduler** | Lib Python de scheduling in-process (cron-like) |
| **Auth.js** | Ex-NextAuth, lib d'auth pour Next.js |
| **Burn rate** | Dépenses mensuelles moyennes incluant les charges fixes (loyer, prêts, abonnements) |
| **Compte de prêt** | Compte bancaire dont le solde représente le capital restant dû (négatif), exposé via Open Banking |
| **DSP2 / PSD2** | Directive européenne sur les services de paiement, impose Open Banking et SCA |
| **Enable Banking** | Fournisseur Open Banking finlandais, propose un tier gratuit "Personal" pour les particuliers |
| **Heartbeat** | Signal périodique d'un worker pour signaler qu'il est vivant |
| **Idempotence** | Propriété d'une opération qu'on peut exécuter plusieurs fois sans effet de bord cumulé |
| **Jauge de sécurité** | Nombre de jours qu'on tient avec le patrimoine actuel au burn rate actuel |
| **LBP** | La Banque Postale |
| **PSU** | Payment Service User — l'utilisateur final dans la terminologie DSP2 |
| **PWA** | Progressive Web App — site web installable sur iOS / Android comme une app native |
| **`pytr`** | Lib Python OSS qui parle au WebSocket interne de Trade Republic |
| **RSC** | React Server Components — composants exécutés côté serveur, pas de JS envoyé au client |
| **SCA** | Strong Customer Authentication — authentification forte (DSP2) avec 2 facteurs minimum |
| **Tailscale Serve** | Feature Tailscale qui expose un service en HTTPS sur `*.ts.net` automatiquement |
| **Tailscale Funnel** | Sous-feature qui ouvre un service Tailscale à Internet public (gratuit pour 1-2 ports) |
| **YNAB** | You Need A Budget — app PFM commerciale, dont l'auteur (Adrien) hérite ses catégories |

---

**Fin du spec.**
