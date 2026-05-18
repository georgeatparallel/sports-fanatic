# CLAUDE.md — Sports Fanatic

MLB SEO and subscription platform. Elixir/Phoenix 1.7 application with a
Python FastAPI microservice bridge, PostgreSQL 16, and Valkey caching.

---

## Project Purpose

Two-layer MLB platform plus a marketing layer:

1. Public SEO layer — granular crawlable pages for every player, team, daily
   lineup, news item, and injury report. Server-rendered HTML with JSON-LD,
   Open Graph, Twitter Cards. Cached in Valkey. Lighthouse SEO >= 95.
2. Premium subscription layer — AI scouting reports and Game Day Magazines
   gated behind Stripe. Three plans: 7-day trial, Monthly $9.99, Yearly $79.99.
3. Marketing layer — X (Twitter) auto-posting agent (see
   `lib/sports_fanatic/x/CLAUDE.md`).

---

## Key Commands

```bash
# Start everything (Docker required)
docker compose up -d
docker compose exec web mix ecto.setup

# Dev server (no Docker)
mix phx.server          # http://localhost:4000
iex -S mix phx.server   # interactive shell

# Tests
mix test.unit           # pure unit tests, no database required
mix test                # all tests (requires PostgreSQL)

# Database
mix ecto.migrate        # apply pending migrations
mix ecto.reset          # drop + recreate + migrate + seed

# Assets
mix assets.build        # compile Tailwind + esbuild
mix assets.deploy       # minified production build

# Format
mix format
```

---

## Architecture Summary

```
Browser → Phoenix Router
           ├── /mlb/* (SEO controllers + NewsLive)        → Valkey cache → Postgres
           ├── /premium/* (subscription-gated LiveView)
           ├── /admin (Joshua-gated AdminLive)
           ├── /webhooks/stripe (StripeWebhookController)
           └── /admin/x/oauth/* (XOAuthController, single org account)

Background workers (Oban) → Python Bridge (FastAPI :8000)
                          → Valkey cache + Postgres + Phoenix PubSub

Marketing: X (Twitter) Agent
  XPostSchedulerWorker (daily) → 3 jittered MainPostWorker jobs
                              → XContentAgent → Python Bridge /x-agent/draft-post
                              → SportsFanatic.X.post_tweet/2 → X API v2
                              → EngagementWatcherWorker (every 5 min × 18)
```

Subsystem-level diagrams live in the relevant sub-folder CLAUDE.md files.

---

## Plug Pipelines

```
:browser              — accepts html, fetch_session, LiveFlash, root layout, CSRF,
                         secure headers, FetchCurrentUser

:require_auth         — RequireAuthenticated (redirects to /login)

:require_subscription — RequireAuthenticated + SubscriptionGate

:require_admin        — RequireAuthenticated + RequireAdmin (user.is_admin)
                         NOTE: the live /admin route is gated by :require_joshua,
                         not :require_admin.

:require_joshua       — RequireJoshua (passphrase session flag)

:joshua_rate_limit    — JoshuaRateLimiter (per-IP throttle on /joshua/login)

:stripe_webhook       — accepts json, CacheRawBody, VerifyStripeWebhook
```

---

## Slug Conventions

- Team slugs: `new-york-yankees`, `los-angeles-dodgers`, `st-louis-cardinals`
- Player slugs: `aaron-judge`, `shohei-ohtani` (full name, lowercase, hyphenated)
- Collision handling: numeric suffix on same team (`john-smith-2`)
- `Slug.slugify/1` lives in `lib/sports_fanatic/mlb/team.ex` (top-level module).
  Future refactor: rename to `SportsFanatic.Slug` (tracked as CODE-001 in
  `docs/KNOWN_ISSUES.md`).

---

## Routing Index

One line per logical group. Details live in the owning sub-folder CLAUDE.md.

| Group | Path | Owner |
|-------|------|-------|
| Home / chat | `/`, `/chat` | `lib/sports_fanatic_web/live/CLAUDE.md` |
| Players | `/mlb/players`, `/mlb/players/:team_slug/:player_slug` | `lib/sports_fanatic_web/controllers/CLAUDE.md` |
| Teams | `/mlb/teams`, `/mlb/teams/:team_slug` | `lib/sports_fanatic_web/controllers/CLAUDE.md` |
| Lineups | `/mlb/lineups/:date` | `lib/sports_fanatic_web/controllers/CLAUDE.md` |
| News | `/mlb/news`, `/mlb/news/:date`, `/mlb/news/:date/:slug` | `lib/sports_fanatic_web/live/CLAUDE.md` |
| Scouting | `/mlb/scouting/:team_slug/:player_slug` | `lib/sports_fanatic_web/controllers/CLAUDE.md` |
| Game Day | `/mlb/game-day/:date/:slug` | `lib/sports_fanatic_web/controllers/CLAUDE.md` |
| Injury Report | `/mlb/injury-report`, `/mlb/injury-report/:player_slug` | `lib/sports_fanatic/x/CLAUDE.md` |
| Feeds | `/feeds`, `/feeds/:id` | `lib/sports_fanatic_web/live/CLAUDE.md` |
| Sitemaps | `/sitemap.xml`, `/sitemaps/:type`, `/robots.txt` | `lib/sports_fanatic_web/controllers/CLAUDE.md` |
| Auth | `/register`, `/login`, `/logout` | `lib/sports_fanatic_web/controllers/CLAUDE.md` |
| Subscriptions | `/subscribe/*`, `/webhooks/stripe` | `lib/sports_fanatic_web/controllers/CLAUDE.md` |
| Premium | `/premium/*` | `lib/sports_fanatic_web/live/CLAUDE.md` |
| Joshua / admin | `/joshua/*`, `/admin` | `lib/sports_fanatic_web/live/CLAUDE.md` |
| X OAuth | `/admin/x/oauth/*` | `lib/sports_fanatic/x/CLAUDE.md` |

---

## Documentation Placement Rule

When updating any `CLAUDE.md` content, follow these rules in order:

1. **Most-specific owner wins.** Place documentation in the most-specific folder
   that fully owns the concept. If a worker is documented, the canonical home is
   `lib/sports_fanatic/workers/CLAUDE.md`, not the root.
2. **Root is for cross-cutting only.** The root `CLAUDE.md` carries: project
   purpose, top-level architecture diagram, key commands, plug pipelines, slug
   conventions, a one-line routing index, this placement rule, and an index of
   sub-folder `CLAUDE.md` files. Nothing else.
3. **Move when a section grows past ~50 lines** or applies only to one folder's
   contents. Replace with a one-line pointer in the original location.
4. **Never duplicate.** If a fact lives in a sub-folder `CLAUDE.md`, the root
   refers to it. If two sub-folders both touch a concept, promote the shared
   part up to the lowest common ancestor folder.
5. **Always breadcrumb.** Every sub-folder `CLAUDE.md` starts with the line
   `Parent: ../CLAUDE.md` (or the appropriate relative path back to root).
6. **Always update, never append.** When the underlying fact changes, edit the
   existing line — do not append a new "Updated:" line.
7. **One source of truth for the index.** When you create a new sub-folder
   `CLAUDE.md`, add it to the index in the root file in the same commit.

---

## Sub-folder CLAUDE.md Index

- [`docs/KNOWN_ISSUES.md`](docs/KNOWN_ISSUES.md) — security and code TODOs (SEC-*, CHAT-*, AGENTS-*, CODE-*)
- [`lib/sports_fanatic/CLAUDE.md`](lib/sports_fanatic/CLAUDE.md) — Elixir contexts, cache, storage, file layout
- [`lib/sports_fanatic/agents/CLAUDE.md`](lib/sports_fanatic/agents/CLAUDE.md) — Jido-pattern action behaviour, NewsAgent
- [`lib/sports_fanatic/chat_bot/CLAUDE.md`](lib/sports_fanatic/chat_bot/CLAUDE.md) — chat history, query clustering
- [`lib/sports_fanatic/external_apis/CLAUDE.md`](lib/sports_fanatic/external_apis/CLAUDE.md) — Exa, FantasyNerds, MLB Stats, Open-Meteo clients
- [`lib/sports_fanatic/predictions/CLAUDE.md`](lib/sports_fanatic/predictions/CLAUDE.md) — Hit predictions pipeline (`/predictions`)
- [`lib/sports_fanatic/workers/CLAUDE.md`](lib/sports_fanatic/workers/CLAUDE.md) — Oban workers + crontab
- [`lib/sports_fanatic/x/CLAUDE.md`](lib/sports_fanatic/x/CLAUDE.md) — X (Twitter) marketing agent
- [`lib/sports_fanatic_web/CLAUDE.md`](lib/sports_fanatic_web/CLAUDE.md) — SEO + date nav conventions
- [`lib/sports_fanatic_web/live/CLAUDE.md`](lib/sports_fanatic_web/live/CLAUDE.md) — LiveView events
- [`lib/sports_fanatic_web/controllers/CLAUDE.md`](lib/sports_fanatic_web/controllers/CLAUDE.md) — controller conventions
- [`priv/repo/migrations/CLAUDE.md`](priv/repo/migrations/CLAUDE.md) — schemas + migration list
- [`python_bridge/CLAUDE.md`](python_bridge/CLAUDE.md) — Python Bridge architecture + endpoints
- [`scripts/CLAUDE.md`](scripts/CLAUDE.md) — DB backup/restore scripts
- [`assets/CLAUDE.md`](assets/CLAUDE.md) — Tailwind, esbuild, LiveView JS hooks
- [`config/CLAUDE.md`](config/CLAUDE.md) — environment config, Oban setup

---

## Environment Variables (cross-cutting summary)

Detailed in the owning sub-folder CLAUDE.md. Quick map of what must be set:

| Var | Owner CLAUDE.md |
|-----|------------------|
| `ANTHROPIC_API_KEY` | `python_bridge/CLAUDE.md` |
| `EXA_API_KEY` | `lib/sports_fanatic/external_apis/CLAUDE.md` |
| `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` | `lib/sports_fanatic_web/controllers/CLAUDE.md` |
| `NEWS_S3_BUCKET`, `NEWS_S3_ENABLED`, `AWS_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` | `lib/sports_fanatic/CLAUDE.md` |
| `X_CLIENT_ID`, `X_CLIENT_SECRET`, `X_REDIRECT_URI`, `X_TOKEN_ENCRYPTION_KEY`, `X_DAILY_CAP_MILLS`, `X_ACCOUNT_HANDLE` | `lib/sports_fanatic/x/CLAUDE.md` |
| `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE`, `S3_BUCKET` | `scripts/CLAUDE.md` |
| `JOSHUA_USERNAME`, `JOSHUA_PASSWORD` | `lib/sports_fanatic_web/live/CLAUDE.md` |
| `VALKEY_URL`, `PYTHON_BRIDGE_URL` | `config/CLAUDE.md` |
| `OPENMETEO_API_KEY`, `PREDICTIONS_INITIAL_SEED_FROM`, `PREDICTIONS_INITIAL_SEED_CONCURRENCY`, `PREDICTIONS_HISTORICAL_BATCH_DAYS`, `PREDICTIONS_OPEN_METEO_TIMEOUT_MS` | `lib/sports_fanatic/predictions/CLAUDE.md` |
