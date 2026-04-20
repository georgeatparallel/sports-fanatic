# Sports Fanatic

MLB SEO and subscription platform — granular public pages for every player, team, lineup, and game, with AI-generated premium content (scouting reports, Game Day Magazines) and real-time live-game updates for subscribers.

## Quick Start

1. Copy the environment file and fill in your API keys:
   ```bash
   cp .env.example .env
   # Edit .env with real values
   ```
2. Start all services:
   ```bash
   docker compose up -d
   ```
3. Run database migrations and seed data:
   ```bash
   docker compose exec web mix ecto.setup
   ```
4. Open [http://localhost:4000](http://localhost:4000)

For local development without Docker, see [Installation](#installation).

---

## Prerequisites

| Dependency | Version | Notes |
|------------|---------|-------|
| Elixir | ~> 1.14 | Via [asdf](https://asdf-vm.com/) or [mise](https://mise.jdx.dev/) |
| Erlang/OTP | 25+ | Installed alongside Elixir |
| Docker & Docker Compose | 24+ | For PostgreSQL, Valkey, Python bridge |
| Python | 3.11+ | Only needed if running `python_bridge` outside Docker |
| Node.js | 18+ | Required by `esbuild` / Tailwind CSS asset pipeline |

---

## Installation

### With Docker (recommended)

```bash
# Clone and enter the project
git clone <repo-url> sports-fanatic
cd sports-fanatic

# Configure environment
cp .env.example .env
# Set SECRET_KEY_BASE (generate with: mix phx.gen.secret)
# Set API keys: FANTASY_NERDS_API_KEY, ANTHROPIC_API_KEY, EXA_API_KEY
# Set Stripe keys: STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET, STRIPE_PRICE_MONTHLY, STRIPE_PRICE_YEARLY

# Start infrastructure (db, cache, python-bridge) + the Phoenix app
docker compose up -d

# Run migrations and seed
docker compose exec web mix ecto.setup
```

### Without Docker (development)

```bash
# Install Elixir dependencies
mix deps.get

# Install JS/CSS assets
mix assets.setup

# Start PostgreSQL and Valkey locally (e.g., via Homebrew or your OS package manager)
# Adjust DATABASE_URL and VALKEY_URL in .env if needed

# Start the Python bridge separately
cd python_bridge
pip install -r requirements.txt
uvicorn src.main:app --reload --port 8000
cd ..

# Create and migrate the database
mix ecto.setup

# Start the Phoenix server
mix phx.server
```

The app runs at [http://localhost:4000](http://localhost:4000).

---

## Environment Variables

Copy `.env.example` to `.env` and set the values below. Variables without a default are **required**.

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `SECRET_KEY_BASE` | Phoenix secret key — generate with `mix phx.gen.secret` | — | Yes |
| `PHX_HOST` | Public hostname for URL generation | `localhost` | Yes (prod) |
| `DATABASE_URL` | PostgreSQL connection string | `ecto://postgres:postgres@localhost:5432/sports_fanatic` | Yes |
| `VALKEY_URL` | Valkey (Redis-compatible) connection URL | `redis://localhost:6379` | Yes |
| `PYTHON_BRIDGE_URL` | Internal URL for the Python ML bridge | `http://localhost:8000` | Yes |
| `FANTASY_NERDS_API_KEY` | FantasyNerds API key (lineups, news) | — | Yes |
| `ANTHROPIC_API_KEY` | Anthropic Claude API key (content generation) | — | Yes |
| `EXA_API_KEY` | Exa AI search API key (scouting sources) | — | Yes |
| `STRIPE_SECRET_KEY` | Stripe secret key (`sk_test_...` or `sk_live_...`) | — | Yes |
| `STRIPE_WEBHOOK_SECRET` | Stripe webhook signing secret (`whsec_...`) | — | Yes |
| `STRIPE_PRICE_MONTHLY` | Stripe Price ID for the $9.99/mo plan | — | Yes |
| `STRIPE_PRICE_YEARLY` | Stripe Price ID for the $79.99/yr plan | — | Yes |

> For local Stripe webhook testing, start the Stripe CLI dev profile:
> ```bash
> docker compose --profile dev up stripe-cli
> ```

---

## Architecture

```mermaid
graph TB
    subgraph "Client Layer"
        Browser[Browser / Crawler]
    end

    subgraph "Phoenix Application"
        Router[Phoenix Router]
        SEOControllers[SEO Controllers\nStatic HTML]
        LiveViews[LiveView Modules\nPremium Real-Time]
        AuthPlug[Auth Plug Pipeline]
        SubGate[Subscription Gate]
        StripeWebhook[Stripe Webhook Controller]
    end

    subgraph "Data Layer"
        PG[(PostgreSQL 16)]
        VK[(Valkey Cache)]
    end

    subgraph "Python Bridge (FastAPI)"
        FastAPI[FastAPI Service :8000]
        HitModel[Hit Prediction GBT]
        HRModel[HR Prediction GBT]
        MonteCarlo[Monte Carlo Engine]
        ScoutGen[Scouting Generator]
        GameDayGen[Game Day Generator]
    end

    subgraph "External APIs"
        FN[FantasyNerds]
        MLB[MLB Stats API]
        Exa[Exa AI Search]
        Claude[Anthropic Claude]
        Stripe[Stripe]
        Weather[Open-Meteo]
    end

    subgraph "Background Workers (Oban)"
        DataFetcher[Data Fetch Workers]
        ContentGen[Content Generation Workers]
        CacheWarmer[Cache Warming Workers]
        SitemapGen[Sitemap Generator]
    end

    Browser --> Router
    Router --> SEOControllers
    Router --> LiveViews
    Router --> StripeWebhook
    SEOControllers --> AuthPlug --> SubGate
    LiveViews --> AuthPlug

    SEOControllers --> VK
    SEOControllers --> PG
    LiveViews --> PG

    DataFetcher --> FN & MLB & Weather --> PG
    ContentGen --> FastAPI --> PG
    ContentGen --> VK

    FastAPI --> HitModel & HRModel & MonteCarlo & ScoutGen & GameDayGen
    FastAPI --> Exa & Claude & MLB

    StripeWebhook --> Stripe
    CacheWarmer --> VK
    SitemapGen --> PG
```

### Key Architectural Decisions

**SEO controllers vs LiveView** — All public pages (`/mlb/*`) use Phoenix controllers that return fully rendered HTML. This ensures Google and other crawlers receive complete content without JavaScript execution. Premium subscriber pages (`/premium/*`) use Phoenix LiveView for WebSocket-based real-time updates (live scores, in-game predictions).

**Python bridge** — ML models (GradientBoosting for hit/HR prediction, Monte Carlo simulation) and AI content generation (scouting reports, Game Day Magazines via Claude) live in a Python FastAPI microservice. It runs on the internal Docker network so Python crashes do not affect the Elixir VM. Phoenix communicates with it over HTTP via `SportsFanatic.PythonBridge` with a circuit breaker (3-failure threshold, 5-minute cooldown).

**Oban for background jobs** — A PostgreSQL-backed job queue handles the content pipeline: data fetching from FantasyNerds and MLB Stats API, ML predictions, AI content generation, cache warming, and sitemap generation. Jobs survive application restarts and retry with exponential backoff.

**Valkey caching** — SEO page HTML fragments are cached in Valkey with short TTLs (2–15 minutes depending on content type) so pages load in under 200 ms. Cache is invalidated proactively when new content is generated. The top 200 players, all 30 teams, and today's lineups are pre-warmed after every content generation cycle.

---

## Project Structure

```
sports-fanatic/
├── lib/
│   ├── sports_fanatic/              # Core business logic
│   │   ├── accounts/                # User, Session schemas
│   │   ├── accounts.ex              # Auth context (register, login, sessions)
│   │   ├── billing/                 # Subscription schema
│   │   ├── billing.ex               # Stripe webhook handling
│   │   ├── cache.ex                 # Valkey wrapper + TTL strategy
│   │   ├── content/                 # ScoutingReport, GameDayMagazine, NewsItem, Sitemap schemas
│   │   ├── external_apis/           # FantasyNerds API client
│   │   ├── mlb/                     # Sport, Team, Player, Venue, Game, Lineup, Pick schemas
│   │   ├── python_bridge.ex         # HTTP client + circuit breaker
│   │   ├── python_bridge/           # CircuitBreaker + HealthCheck GenServers
│   │   └── workers/                 # 9 Oban workers
│   └── sports_fanatic_web/          # Phoenix web layer
│       ├── components/              # SEO components (json_ld, breadcrumbs, subscribe_cta)
│       ├── controllers/             # SEO page controllers + auth/subscription controllers
│       ├── live/                    # 6 LiveView modules (dashboard, scouting, game day, archives)
│       └── plugs/                   # FetchCurrentUser, RequireAuthenticated, SubscriptionGate,
│                                    #   VerifyStripeWebhook, CacheRawBody
├── python_bridge/
│   ├── src/
│   │   ├── api/                     # predict.py, scouting.py, gameday.py
│   │   ├── models/                  # hit_model.py, hr_model.py (GradientBoosting)
│   │   ├── simulation/              # Monte Carlo engine (NumPy-vectorized)
│   │   ├── config.py
│   │   └── main.py                  # FastAPI app entrypoint
│   ├── Dockerfile
│   └── requirements.txt
├── priv/
│   └── repo/
│       ├── init.sql                 # Schema creation + PostgreSQL extensions
│       ├── migrations/              # 5 migration files
│       └── seeds.exs
├── test/                            # ExUnit tests (63 pure unit + 108 DB-dependent)
├── docker-compose.yml               # 5 services: web, db, cache, python-bridge, stripe-cli
├── Dockerfile                       # Multi-stage Phoenix release build
└── .env.example                     # Environment variable template
```

---

## Public URL Structure

All public pages are server-rendered (no JavaScript required for crawlers) and include JSON-LD structured data, Open Graph tags, and Twitter Card meta tags.

| Pattern | Example | Description |
|---------|---------|-------------|
| `/` | `/` | Landing page — today's games and featured content |
| `/mlb/players` | `/mlb/players` | All players index |
| `/mlb/players/:team/:player` | `/mlb/players/new-york-yankees/aaron-judge` | Player profile |
| `/mlb/teams` | `/mlb/teams` | All teams index |
| `/mlb/teams/:team` | `/mlb/teams/los-angeles-dodgers` | Team page |
| `/mlb/lineups/:date` | `/mlb/lineups/2026-04-19` | Daily confirmed lineups |
| `/mlb/news/:date` | `/mlb/news/2026-04-19` | Daily news index |
| `/mlb/news/:date/:slug` | `/mlb/news/2026-04-19/judge-returns` | News item |
| `/mlb/scouting/:team/:player` | `/mlb/scouting/new-york-yankees/aaron-judge` | Scouting preview (free) |
| `/mlb/game-day/:date/:slug` | `/mlb/game-day/2026-04-19/yankees-vs-dodgers` | Game Day preview (free) |

Premium routes (`/premium/*`) require an active subscription.

---

## Subscription Plans

| Plan | Price | Features |
|------|-------|---------|
| Free | $0 | Public SEO pages, truncated scouting previews |
| 7-day Trial | $0 for 7 days | Full access, then auto-converts to paid plan |
| Monthly | $9.99/mo | Full scouting reports, Game Day Magazines, live game updates |
| Yearly | $79.99/yr | Same as monthly, ~33% discount |

Payments are processed via Stripe Checkout Sessions. No card data touches the server.

---

## Content Pipeline

The Oban background job pipeline runs on a schedule and produces all content:

| Worker | Schedule | Purpose |
|--------|----------|---------|
| `FetchScheduleWorker` | 6 AM ET daily | Fetch day's schedule from MLB Stats API |
| `FetchLineupsWorker` | Every 30 min, 8 AM–8 PM ET | Fetch confirmed lineups from FantasyNerds |
| `FetchNewsWorker` | Every 2 hours | Fetch player news from FantasyNerds |
| `GeneratePredictionsWorker` | Triggered after lineups | Call Python bridge for hit/HR probabilities |
| `GenerateScoutingWorker` | 7 AM ET daily | Generate scouting reports for today's players |
| `GenerateGameDayWorker` | 9 AM ET daily | Generate Game Day Magazines for all games |
| `WarmCacheWorker` | After content generation | Pre-populate Valkey for high-traffic pages |
| `GenerateSitemapWorker` | Every 6 hours | Regenerate all XML sitemaps |
| `ResolveGamesWorker` | Every 30 min after 7 PM ET | Fetch completed game results |
| `CleanupWorker` | 3 AM ET daily | Purge expired sessions |

---

## API Reference

### Python Bridge (internal, port 8000)

The Python FastAPI service is only accessible on the internal Docker network.

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Health check — confirms models are loaded |
| `POST` | `/predict/hit` | Batch hit probability predictions (GradientBoosting) |
| `POST` | `/predict/hr` | Batch HR probability + exit velocity predictions |
| `POST` | `/simulate/monte-carlo` | Monte Carlo game simulation (NumPy-vectorized, 10k trials) |
| `POST` | `/scouting/search` | Search player news via Exa AI |
| `POST` | `/scouting/generate` | Generate scouting report via Claude |
| `POST` | `/gameday/generate` | Generate Game Day Magazine via Claude |

### Stripe Webhooks

The webhook endpoint is at `POST /webhooks/stripe`. Requests must carry a valid `Stripe-Signature` header.

| Event | Action |
|-------|--------|
| `checkout.session.completed` | Create subscription record, set user tier |
| `invoice.paid` | Extend subscription period |
| `invoice.payment_failed` | Set status to `past_due` |
| `customer.subscription.updated` | Sync plan and status changes |
| `customer.subscription.deleted` | Downgrade user to free tier |

---

## Running Tests

```bash
# Unit tests only (no database required)
mix test.unit

# All tests (requires running PostgreSQL)
mix test

# Run tests with database setup from scratch
MIX_ENV=test mix ecto.create && MIX_ENV=test mix ecto.migrate && mix test
```

**Test summary**: 63 pure unit tests (schema changesets, cache key builders, circuit breaker state machine) + 108 database-dependent integration tests (context operations, controllers, plugs).

---

## Development

```bash
# Install dependencies
mix deps.get && mix assets.setup

# Build assets
mix assets.build

# Start server with live reload
mix phx.server

# Interactive shell
iex -S mix phx.server

# Database commands
mix ecto.reset           # Drop, recreate, migrate, seed
mix ecto.migrate         # Apply pending migrations

# Code formatting
mix format

# Phoenix Live Dashboard (dev only)
# http://localhost:4000/dev/dashboard
```

---

## Deployment

The project uses a multi-stage Docker build producing an Erlang release.

```bash
# Build the release image
docker build -t sports-fanatic:latest .

# Production compose (adjust env vars for production values)
docker compose up -d

# Run migrations in production
docker compose exec web /app/bin/sports_fanatic eval "SportsFanatic.Release.migrate()"
```

Production notes:
- `SECRET_KEY_BASE` must be set and remain stable across deployments (signs session cookies).
- `PHX_HOST` must be set to the public hostname.
- Remove host port mappings for `db` (5432), `cache` (6379), and `python-bridge` (8000) in production — these services should only be accessible on the internal Docker network.
- Place a reverse proxy (nginx, Caddy, or Cloudflare) in front of Phoenix on port 4000.
- The `stripe-cli` service uses `profiles: [dev]` and will not start in production by default.

---

## Security

The platform is designed with the following security controls:

- **Passwords**: bcrypt with 12 rounds via `bcrypt_elixir`.
- **Sessions**: 256-bit random tokens, stored server-side, 30-day expiry, dropped on logout.
- **CSRF**: Phoenix built-in CSRF protection on all browser forms.
- **Stripe**: Webhook signatures verified via `Stripe-Signature` header before processing.
- **Auth redirects**: The `return_to` parameter should be validated as a relative path before use (see SEC-002 in `.on-loop/agent-notes/security.md`).
- **Content rendering**: AI-generated and external API content should be sanitized before rendering with `raw/1` (see SEC-001).
- **Python bridge**: Accessible only on the internal Docker network in production.
- **Rate limiting**: Auth endpoints should have Valkey-backed rate limiting (5 attempts/IP/5 min) — not yet implemented (SEC-003).

Known security findings requiring remediation before production are documented in `.on-loop/agent-notes/security.md`.

To report a security vulnerability, open a private issue or contact the maintainer directly.

---

## License

Private — all rights reserved.
