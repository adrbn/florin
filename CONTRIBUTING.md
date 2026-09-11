# Contributing to Florin

Thanks for looking. Florin is built and used daily by one person on their own money, so
issues and pull requests are read carefully and answered — just not always the same day.

## Before you start

- **Bugs:** open an issue with the platform (Mac, iPhone, web), the version from
  Settings → About, and what you expected against what you saw. A figure that looks wrong
  is worth reporting with the numbers involved; they are what get it fixed.
- **Features:** open an issue first if the change is bigger than a small fix, so we can
  agree on the shape before you spend an evening on it.
- **Security:** do not open a public issue — see [SECURITY.md](SECURITY.md).

## Two rules that matter here

1. **`packages/db-pg` and `packages/db-sqlite` are deliberate twins.** The same schema and
   query surface over two drivers. A query, schema or sync fix almost always belongs in
   **both**, and so do the `apps/web` / `apps/desktop` server actions that wrap them. A new
   table also belongs in the iPhone ledger (`apps/ios/Florin/Local/LocalSchema.swift`) and
   in both mirror scripts under `scripts/`.
2. **Figures are checked against something real.** A change to how a number is computed —
   a balance, a loan's remaining capital, a savings rate, a projection — comes with a test
   that pins it to a bank statement, a documented case, or an independent calculation.
   Not against the code's own previous output.

## Setting up

### Web, desktop and shared packages

Use **Node 22** and pnpm (the version is pinned in `package.json`). `better-sqlite3` has
no prebuilt binary for newer Node majors and does not compile against them, so a newer
Node breaks `pnpm install` for the whole workspace.

```bash
pnpm install
make dev                                     # web, against the Docker Postgres
cd apps/desktop && pnpm dev                  # desktop
```

Run the tests from the workspace, not the repo root — the root config does not resolve
the web app's `@/` path alias, and files that fail to import are silently skipped:

```bash
pnpm --filter @florin/web exec vitest run
```

### iPhone

Xcode 26 or newer and [XcodeGen](https://github.com/yonaskolb/XcodeGen). `project.yml` is
the source of truth; regenerate the project after adding or removing a file.

```bash
cd apps/ios
xcodegen generate
xcodebuild test -project Florin.xcodeproj -scheme Florin \
  -destination 'platform=iOS Simulator,name=iPhone 17'   # any simulator you have
```

The on-device strings live in `apps/ios/Florin/Local/Resources/Strings.json`, in English,
French, German, Dutch, Italian, Spanish, Portuguese and Catalan. A new key goes into all eight.

## Pull requests

- One change per pull request, with a description of what it fixes and how you checked it.
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/):
  `feat:`, `fix:`, `perf:`, `refactor:`, `docs:`, `test:`, `ci:`, `chore:` — with a scope
  where it helps (`fix(ios): …`).
- CI runs the typecheck and the test suite on every pull request. It has to be green.
- A version bump belongs in `apps/web`, `apps/desktop` and `apps/ios` together; a test
  fails the build when they drift.

By contributing you agree that your work is released under the project's
[AGPL-3.0](LICENSE) licence.
