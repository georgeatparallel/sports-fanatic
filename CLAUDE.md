# CLAUDE.md — Sports Fanatic

MLB SEO and subscription platform. Elixir/Phoenix 1.7 application with a Python FastAPI microservice bridge, PostgreSQL 16, and Valkey (Redis-compatible) caching.

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
mix test.unit           # 63 pure unit tests, no database required
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

## Project Purpose

Two-layer MLB platform:

1. **Public SEO layer** — granular, crawlable pages for every MLB player, team, daily lineup, and news item. Server-rendered HTML with JSON-LD structured data, Open Graph tags, and Twitter Cards. Cached in Valkey. Lighthouse SEO target: >= 95.

2. **Premium subscription layer** — AI-generated scouting reports and Game Day Magazines gated behind Stripe subscriptions. Phoenix LiveView for real-time in-game updates. Three plans: 7-day free trial, Monthly ($9.99), Yearly ($79.99).

---

## Architecture Summary

```
Browser → Phoenix Router
           ├── /mlb/* → SEO Controllers → (Valkey cache hit) → HTML response
           │                            → (cache miss) → PostgreSQL → render → cache → HTML
           ├── /premium/* → LiveView (subscription-gated, WebSocket)
           └── /webhooks/stripe → StripeWebhookController

Oban workers (background)
  FetchSchedule / FetchLineups / FetchNews → PostgreSQL
  GeneratePredictions → Python Bridge (FastAPI :8000)
  GenerateScouting / GenerateGameDay → Python Bridge → Claude API → PostgreSQL
  WarmCache → Valkey
  GenerateSitemap → PostgreSQL

Python Bridge (python_bridge/ → Docker service on internal network)
  FastAPI + GradientBoosting ML models + Monte Carlo simulation
  Calls: Claude API, Exa AI search, MLB Stats API
```

---

## File Structure

```
lib/sports_fanatic/
  accounts/           User, Session Ecto schemas
  accounts.ex         Accounts context (register, authenticate, session CRUD)
  billing/            Subscription schema
  billing.ex          Stripe webhook handlers (checkout, invoice, subscription events)
  cache.ex            Valkey wrapper — get/set/delete/invalidate_pattern + TTL constants
  content/            ScoutingReport, GameDayMagazine, NewsItem, Sitemap schemas
  external_apis/      FantasyNerds HTTP client
  mlb/                Sport, Team, Player, Venue, Game, ScheduledGame, Lineup, Pick, HrPick
  python_bridge.ex    HTTP client for Python bridge with circuit breaker integration
  python_bridge/      CircuitBreaker GenServer + HealthCheck GenServer
  workers/            10 Oban workers (fetch_lineups, fetch_schedule, fetch_news,
                       generate_predictions, generate_scouting, generate_game_day,
                       generate_player_seo, warm_cache, generate_sitemap, cleanup)

lib/sports_fanatic_web/
  components/         seo_components.ex — json_ld/2, breadcrumbs/1, subscribe_cta/1
  controllers/        Page, Player, Team, Lineup, News, Scouting, GameDay, Sitemap,
                       Auth, Subscription, StripeWebhook controllers + HTML modules
  live/               DashboardLive, ScoutingLive, GameDayLive, GameDayIndexLive,
                       ArchiveScoutingLive, ArchiveGameDayLive, AdminLive
  plugs/              FetchCurrentUser, RequireAuthenticated, RequireAdmin, SubscriptionGate,
                       VerifyStripeWebhook, CacheRawBody
  router.ex           Route definitions — see Routing section below

python_bridge/src/
  api/predict.py      POST /predict/hit, /predict/hr
  api/scouting.py     POST /scouting/search (Exa), /scouting/generate (Claude)
  api/gameday.py      POST /gameday/generate (Claude)
  simulation/engine.py  Monte Carlo engine, NumPy-vectorized, 10k trials
  config.py           Settings from environment variables
  main.py             FastAPI app, routers registered, /health endpoint
```

---

## Routing Conventions

```
/                         PageController :home
/mlb/players              PlayerController :index
/mlb/players/:team/:player PlayerController :show
/mlb/teams                TeamController :index
/mlb/teams/:team          TeamController :show
/mlb/lineups/:date        LineupController :show
/mlb/news/:date           NewsController :index
/mlb/news/:date/:slug     NewsController :show
/mlb/scouting/:team/:player ScoutingController :show   (public preview)
/mlb/game-day/:date/:slug GameDayController :show      (public preview)
/sitemap.xml              SitemapController :index
/sitemaps/:type           SitemapController :show      (players/teams/lineups/news/scouting/gameday)
/robots.txt               SitemapController :robots

/register, /login, /logout, /confirm/:token, /forgot-password, /reset-password/:token
                          AuthController

/subscribe                SubscriptionController :pricing
/subscribe/checkout       SubscriptionController :checkout  (requires auth)
/subscribe/success|cancel SubscriptionController

/webhooks/stripe          StripeWebhookController :handle  (stripe_webhook pipeline)

/premium/dashboard        DashboardLive         (requires subscription)
/premium/scouting/:team/:player ScoutingLive
/premium/game-day/:date/:slug   GameDayLive
/premium/game-day/:date         GameDayIndexLive
/premium/archive/scouting       ArchiveScoutingLive
/premium/archive/game-day       ArchiveGameDayLive

/admin                          AdminLive             (requires admin user, live_session)
```

**Sitemap route note**: The router uses `/sitemaps/:type` (not `/sitemap-:type.xml`) because Phoenix does not support hyphens before dynamic segments.

---

## Plug Pipelines

```
:browser              — accepts html, fetch_session, LiveFlash, root layout, CSRF, secure headers,
                         FetchCurrentUser (always runs, sets conn.assigns.current_user)

:require_auth         — RequireAuthenticated (redirects to /login with return_to if not logged in)

:require_subscription — RequireAuthenticated + SubscriptionGate (redirects to /subscribe if no
                         active subscription or expired)

:require_admin        — RequireAuthenticated + RequireAdmin (redirects to / if user is not an admin)

:stripe_webhook       — accepts json, CacheRawBody (preserves raw body for sig check),
                         VerifyStripeWebhook (validates Stripe-Signature header)
```

---

## Database Schemas

Six PostgreSQL schemas. Migrations are in `priv/repo/migrations/`, init SQL in `priv/repo/init.sql`.

| Schema | Tables | Description |
|--------|--------|-------------|
| `public` | sports, teams, players, venues | Core MLB entities |
| `mlb` | games, scheduled_games, lineups, player_boxscores, player_season_stats, picks, hr_picks, game_weather, park_hr_factors | Game data and predictions |
| `content` | scouting_reports, game_day_magazines, news_items, sitemaps | AI-generated content |
| `accounts` | users, subscriptions, sessions | Auth and billing |
| `system` | pipeline_runs, pipeline_steps, cache_invalidations | Operations |
| `scouting` | (from sports-fan-agent, retained) | |

All UUIDs use `gen_random_uuid()`. `slug` fields follow the pattern `lowercase-hyphenated-name`.

---

## Slug Conventions

- **Team slugs**: `new-york-yankees`, `los-angeles-dodgers`, `st-louis-cardinals`
- **Player slugs**: `aaron-judge`, `shohei-ohtani` (full name, lowercase, hyphenated)
- **Collision handling**: Append numeric suffix for duplicate names on same team: `john-smith-2`
- `Slug.slugify/1` is defined in `lib/sports_fanatic/mlb/team.ex` as a top-level module `Slug`. It is accessible project-wide as `Slug.slugify/1`. Future refactor: rename to `SportsFanatic.Slug`.

---

## Valkey Caching

```
sf:page:player:{team}:{slug}      TTL 5 min
sf:page:team:{slug}               TTL 10 min
sf:page:lineup:today              TTL 2 min
sf:page:lineup:{past-date}        TTL 24 hours
sf:page:news:{date}:{slug}        TTL 5 min
sf:page:scouting:{team}:{slug}    TTL 15 min
sf:page:gameday:{date}:{slug}     TTL 10 min
sf:data:predictions:*             TTL 5 min
sf:sitemap:*                      TTL 6 hours
```

Use `SportsFanatic.Cache.get/1`, `put/3`, `delete/1`, `invalidate_pattern/1`.

---

## Python Bridge

`SportsFanatic.PythonBridge` is the Elixir-side HTTP client. It calls `http://python-bridge:8000` (Docker internal) via `Req`. The circuit breaker (`SportsFanatic.PythonBridge.CircuitBreaker`) trips after 3 consecutive failures and stays open for 5 minutes. `SportsFanatic.PythonBridge.HealthCheck` pings `/health` every 30 seconds.

In production, the `python-bridge` service should not expose port 8000 to the host. The `docker-compose.yml` currently exposes it — remove the `ports` entry for production (SEC-007).

---

## Oban Workers

All workers live in `lib/sports_fanatic/workers/`. They use `use Oban.Worker, queue: :default, max_attempts: 3`.

Cron schedules are defined in `config/config.exs` under `Oban.crontab`. Times are UTC (convert from ET accordingly).

Scheduled cron entries:
- `GeneratePlayerSeoWorker` — 4:00 AM UTC daily
- `GeneratePredictionsWorker` — 9:30 AM UTC daily
- `WarmCacheWorker` — every 15 minutes

To manually enqueue a worker in IEx:
```elixir
%{} |> SportsFanatic.Workers.FetchLineupsWorker.new() |> Oban.insert()
```

---

## Testing Strategy

- **Pure unit tests** (`mix test.unit`): Schema changesets, `Slug.slugify/1`, `has_active_subscription?/1`, cache key builders, circuit breaker state machine. No PostgreSQL required.
- **Integration tests** (`mix test`): Accounts context, billing webhook handlers, controllers, auth plugs. Require PostgreSQL.
- Test data uses `SportsFanatic.DataCase` (SQL sandbox) for DB tests.
- No Mox dependency. Worker tests verify Oban job structure, not external API calls.
- Python bridge and FantasyNerds API are not mocked in current tests.

---

## SEO Template Requirements

Every public controller action must set these assigns on `conn`:

```elixir
conn
|> assign(:page_title, "...")            # used in <title> tag
|> assign(:meta_description, "...")      # max 160 chars
|> assign(:canonical_url, "...")         # self-referencing
|> assign(:og_image, "...")              # Open Graph image URL
|> assign(:json_ld, Jason.encode!(...))  # ALWAYS use Jason.encode!/1, never raw strings
```

The root layout (`root.html.heex`) renders these automatically. JSON-LD must come from `Jason.encode!/1` output to prevent XSS via script injection.

---

## Known Issues and TODOs

| ID | Severity | Description |
|----|----------|-------------|
| SEC-001 | HIGH | Stored XSS: `raw/1` used on external/AI content in news body, game day analysis, JSON-LD. Add `HtmlSanitizeEx` before storing. |
| SEC-002 | HIGH | Open redirect: `return_to` parameter not validated as relative path in `AuthController`. |
| SEC-003 | MEDIUM | Rate limiting not implemented on `/login` and `/register` (spec requires 5/IP/5 min). |
| SEC-004 | MEDIUM | Stripe webhook idempotency not implemented — duplicate events can cause redundant writes. |
| SEC-005 | MEDIUM | `SubscriptionGate` allows access when `subscription_expires_at` is nil for non-free tier. |
| SEC-006 | MEDIUM | `.env` not in `.gitignore`. |
| SEC-007 | MEDIUM | Python bridge port 8000 exposed to host in `docker-compose.yml`. |
| CODE-001 | LOW | `Slug` module is not namespaced (`defmodule Slug` in `team.ex`). Works correctly but should be `SportsFanatic.Slug`. |
| CODE-002 | LOW | `Billing.handle_checkout_completed/1` checks wrong path for trial detection. Trial status should come from `customer.subscription.updated` webhook with `status: "trialing"`. |

Full security audit is in `.on-loop/agent-notes/security.md`.

---

## Common Tasks

**Add a new Oban worker:**
1. Create `lib/sports_fanatic/workers/my_worker.ex` with `use Oban.Worker`.
2. Add to crontab in `config/config.exs` if scheduled.
3. Add to `lib/sports_fanatic/application.ex` supervision if it needs startup configuration.

**Add a new SEO page:**
1. Add route in `router.ex` under the public `:browser` scope.
2. Create controller in `lib/sports_fanatic_web/controllers/`.
3. Create HTML module + HEEx templates.
4. Set SEO assigns (`page_title`, `meta_description`, `canonical_url`, `json_ld`).
5. Add cache read/write in the controller action.
6. Update `GenerateSitemapWorker` to include new URLs.

**Update subscription tier logic:**
- `SportsFanatic.Accounts.has_active_subscription?/1` is the single source of truth.
- `SportsFanatic.Billing` handles all Stripe webhook events.
- `SportsFanaticWeb.Plugs.SubscriptionGate` enforces access at the router level.

**Test Stripe webhooks locally:**
```bash
docker compose --profile dev up stripe-cli
# stripe-cli forwards events from Stripe to http://web:4000/webhooks/stripe
```
