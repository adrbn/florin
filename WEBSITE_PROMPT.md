# Website prompt — Florin landing page

Paste the block below into Claude Design (Opus 4.7). One page, no CMS, ships as static HTML/CSS so it can live on GitHub Pages / Cloudflare Pages / Netlify for free.

---

## PROMPT

Design a single-page marketing landing site for **Florin**, a privacy-first personal finance dashboard. Two products, one brand:

1. **Florin Desktop** — native macOS app. Paid (one-time license, $29). Downloadable `.dmg`. Bank sync, local SQLite, menu bar widget, zero cloud.
2. **Florin Server** — open-source self-hosted web app (AGPL-3.0). Free. `docker compose up`, Postgres, single-admin. Same UI as desktop.

### Positioning

- **Privacy-first alternative to YNAB / Copilot Money / Monarch.** No subscription, no data resale, no telemetry. Your ledger lives on hardware you own.
- **European-first.** Bank linking via Enable Banking (PSD2) covering 2 000+ EU banks — Boursorama, Revolut, N26, Fortuneo, Crédit Agricole, La Banque Postale, Caixa, Deutsche Bank, etc.
- **YNAB-style workflow** — category groups (Needs / Wants / Bills / Savings / Income), review queue, monthly plan, auto-categorization rules.
- **Two deployment shapes, one codebase.** Prosumers pick desktop; self-hosters pick server.

### Audience

European tech-literate prosumers (30–45) frustrated with subscription finance apps, privacy-conscious, comfortable with a `.dmg` or `docker compose`. Secondary: the self-hosting / homelab crowd.

### Page structure (top to bottom)

1. **Hero**
   - Headline: a sharp, confident one-liner. Something like *"Your money. Your machine."* or *"The personal finance app that doesn't phone home."* — propose 2–3 variants.
   - Sub: one sentence that says "native macOS app + self-hosted web, real bank sync via PSD2, zero cloud."
   - Primary CTA: **Download for macOS ($29)**. Secondary CTA: **Self-host for free** (scrolls to the server section or links to GitHub).
   - Visual: a crisp product screenshot — prefer the dashboard with net worth, 12-month patrimony chart, category breakdown. Mock it up if needed; style should read modern/financial: clean monospace numbers, soft gradients, dark mode by default with a light toggle.

2. **Why Florin** — three to four short value cards:
   - **On-device only.** Data never touches our servers. We have no servers.
   - **Real bank sync.** PSD2 via Enable Banking — 2 000+ EU banks, you register your own free app.
   - **YNAB, reimagined.** Plan, review, reflect. Without the subscription.
   - **Two shapes.** Native macOS menu bar app, or self-hosted Docker stack.

3. **Feature tour** — 4–6 screenshots with one-liner captions. Ideas:
   - Dashboard with patrimony forecast
   - Review queue (bulk categorize bank imports)
   - Reflect: 52-week spending heatmap (GitHub-style)
   - Plan tab: monthly budgets with progress bars
   - Menu bar widget (desktop only)
   - Command palette (⌘K)

4. **Two products, one brand** — side-by-side comparison:
   |                    | Florin Desktop                 | Florin Server                  |
   |--------------------|--------------------------------|--------------------------------|
   | Price              | $29 one-time                   | Free, AGPL-3.0                 |
   | Platform           | macOS (Apple Silicon + Intel)  | Docker (any OS)                |
   | Storage            | SQLite (local file)            | Postgres (your server)         |
   | Setup              | Drag-and-drop DMG              | `docker compose up -d`         |
   | Bank sync          | ✅                            | ✅                            |
   | Menu bar widget    | ✅                            | —                             |
   | Auto-updater       | ✅                            | `git pull`                    |
   | Mobile access      | —                             | PWA (phone + tablet)           |

5. **Privacy promise** — one bold paragraph. Open source, inspect the code, no analytics, no tracking SDKs, no third-party aggregation, bank credentials stay between you and your bank. Link to the repo.

6. **FAQ** — collapsible. Cover:
   - Which banks are supported? (2 000+ EU; link to Enable Banking's coverage map)
   - Why pay for the desktop app when the server is free? (Convenience: native menu bar, signed binary, auto-update, no Docker.)
   - Is it safe to trust with my bank? (PSD2 read-only access through your own Enable Banking app — credentials never flow through us.)
   - What about iOS / Android? (The web app is PWA-installable. Native mobile isn't on the roadmap.)
   - Will my license work on multiple Macs? (Yes — personal use, all your devices.)
   - Do you sell my data? (No. There's nothing to sell — we can't see it.)

7. **Footer**
   - Links: GitHub, Docs (README), Releases, Issues
   - Made by Adrien · Based in France · AGPL-3.0 for the server, commercial license for the signed desktop binary

### Visual direction

- **Typeface:** system UI sans for body, a crisp display sans (e.g. Tuaf, Geist, Inter) for headlines. Tabular numbers everywhere.
- **Palette:** dark-first with a warm, almost parchment-tinted light theme. Accent: the dusty gold from a Dutch florin coin — not neon, not fintech blue. Secondary: sage green for positive deltas, muted rose for negative.
- **Feel:** confident, understated, slightly artisanal. Think Linear × Things 3 × a private banker's statement. Not bro-y fintech. Not cartoonish.
- **Rounded corners 8–12px**, 1px hairline borders, soft shadows only on hover, generous vertical rhythm.
- **No stock photos.** All imagery is product screenshots or abstract typographic blocks.
- **Motion:** subtle — fade-in on scroll, tiny reveal on feature cards. Nothing bouncy.

### Technical constraints

- Single `index.html` + one CSS file. No framework. No build step. Inline SVG for icons.
- Responsive: mobile-first, one breakpoint at ~768px.
- Lighthouse: 100 / 100 / 100 / 100. No tracking scripts. No fonts from Google — self-host or use system.
- Preload the hero screenshot. Everything else lazy.
- Copy is editable by a non-dev — keep it in one section near the top of the HTML.
- Meta: OG tags, Twitter card, favicon (use the Florin icon — I'll provide `icon.png`).

### Deliverables

1. `index.html` + `styles.css`.
2. Three hero-headline variants so I can pick.
3. Placeholder `<img src="...">` paths for every screenshot slot — I'll swap them in.
4. A one-paragraph "what I'd change if we had another day" note at the end, if anything feels compromised.

Prioritize: (1) copy that converts prosumers who've already paid for YNAB, (2) a hero screenshot that immediately reads *"ah, this is the real thing"*, (3) zero friction from hero to download button.
