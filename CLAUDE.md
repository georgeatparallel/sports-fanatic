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

## Agents System

An LLM-powered agent system lets authenticated users define natural language "settings" (agent tasks) via a sticky command input box on the news feed. Settings are parsed by Claude Haiku into structured search/filter criteria, executed daily at 9am ET, and displayed in an "Agents" tab alongside the existing news feed.

### Command Input

The command input is a sticky `<textarea>` rendered at the top of `NewsLive` on `/mlb/news`, `/mlb/news/:date`, and `/`. Unauthenticated users see the input in a disabled state with a login prompt. Authenticated users can type:

| Command | Description |
|---------|-------------|
| `/settings-apply "<prompt>"` | Creates or updates an agent setting from a natural language description |
| `/settings-clear` | Removes all active settings for the current user |
| (plain text) | Client-side substring filter on the current feed (debounced 300ms); ephemeral, not persisted |

**Constraints**: Maximum 500 characters per prompt. Maximum 20 active settings per user. Maximum 5 `/settings-apply` commands per user per hour (rate-limited at the context layer).

### Settings Lifecycle

1. User submits `/settings-apply "track hr streaks from Aaron Judge"`.
2. `Agents.create_setting/2` inserts a row in `accounts.news_agent_settings` with `status: pending`.
3. `ParseSettingWorker` is enqueued immediately and calls `POST /agents/parse-setting` on the Python Bridge.
4. Claude Haiku parses the prompt into structured criteria (players, teams, leagues, stat filters, categories, domain tags).
5. The setting is updated to `status: active` with `parsed_criteria` populated.
6. `ParseSettingWorker` broadcasts `{:setting_updated, setting}` on PubSub topic `"agent:settings:{user_id}"` so the Agents tab refreshes in real time.

### Daily Execution

`RunNewsAgentsWorker` runs at 9:00 AM ET daily (cron `0 13 * * *`). It:
- Checks the `news_agents_enabled` feature flag; exits early if disabled.
- Fetches all users with `active` settings.
- For each user, calls `Agents.run_all_agents/0` which queries `content.news_items` using ILIKE text matching against player and team names from `parsed_criteria` (Phase 1 simplification).
- Stores results in `accounts.news_agent_results` with matched article IDs and an explanation.
- Updates each setting's `last_run_at` and `status`.

Premium subscribers can trigger immediate execution via the "Run Now" button in the Agents tab, which enqueues `RunNewsAgentsWorker` on demand.

### Agents Tab in AdminLive

`/admin` includes an "Agents" tab with:
- Toggle to enable/disable agent execution globally (`news_agents_enabled` feature flag).
- Cron schedule display and override field (default: `0 13 * * *`).
- Read-only table of all users' active settings.
- "Run All Agents" button for manual triggering.

### Entity Display in News Feed

Player and team associations resolved by `EntityMatcher` are now visible in news article cards:
- Player names render as links to `/mlb/players/:team/:player`.
- Team names render with team abbreviation badges and links to `/mlb/teams/:team`.
- League badges (AL/NL) are derived from `team.league` added to feed data in `News.build_feed/1`.

---

## Architecture Summary

```
Browser → Phoenix Router
           ├── /mlb/news, /mlb/news/:date → NewsLive (LiveView, WebSocket)
           │     ├── (connected) subscribes to Phoenix PubSub "news:feed:{date}" + "news:feed"
           │     │                                              + "agent:settings:{user_id}"
           │     └── reads Valkey cache → (miss) → PostgreSQL
           ├── /mlb/news/today → NewsController :redirect_today → 302 /mlb/news/<current ET date>
           ├── /mlb/* → SEO Controllers → (Valkey cache hit) → HTML response
           │                            → (cache miss) → PostgreSQL → render → cache → HTML
           ├── /premium/* → LiveView (subscription-gated, WebSocket)
           └── /webhooks/stripe → StripeWebhookController

Oban workers (background)
  FetchSchedule / FetchLineups → PostgreSQL
  FetchNews (every 1 min) → S3 (raw JSON) → Python Bridge /news/analyze → PostgreSQL
                           → Valkey invalidate → Phoenix PubSub broadcast → NewsLive updates
  ParseSettingWorker (async, per-setting) → Python Bridge /agents/parse-setting → Claude Haiku
                                          → PostgreSQL UPDATE setting status=active
                                          → PubSub broadcast agent:settings:{user_id}
  RunNewsAgentsWorker (daily 9am ET) → Agents context → PostgreSQL (match news_items)
                                     → Python Bridge /agents/execute (Phase 2)
                                     → PostgreSQL INSERT news_agent_results
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
  agents.ex           Agents context — create_setting/2, list_user_settings/1, delete_setting/2,
                       run_all_agents/0; enforces max 20 settings/user and 5/user/hour rate limit
  agents/             news_agent_setting.ex — Ecto schema (id, user_id, raw_prompt, parsed_criteria JSONB,
                         status, last_run_at, last_result JSONB, error_message)
                       news_agent_result.ex — Ecto schema (id, user_id, setting_id, matched_news_item_ids UUID[],
                         exa_results JSONB, explanation, run_date)
  billing/            Subscription schema
  billing.ex          Stripe webhook handlers (checkout, invoice, subscription events)
  cache.ex            Valkey wrapper — get/set/delete/invalidate_pattern + TTL constants
  content/            ScoutingReport, GameDayMagazine, NewsItem (+ domain_tags field), Sitemap schemas
  external_apis/      FantasyNerds HTTP client
  mlb/                Sport, Team, Player, Venue, Game, ScheduledGame, Lineup, Pick, HrPick
  news.ex             News context — cached feed reads, entity-resolved list, get_cached_feed/1,
                       nearest_news_date_before/1, nearest_news_date_after/1
                       Feed data now includes domain_tags and team.league for badge display
  news/               entity_matcher.ex — fuzzy player/team matching (jaro_distance, threshold 0.85)
  python_bridge.ex    HTTP client for Python bridge with circuit breaker integration
                       Added: parse_setting/2, execute_agents/2
  python_bridge/      CircuitBreaker GenServer + HealthCheck GenServer
  storage.ex          S3 storage module — put_object/3, get_object/2, news_article_key/2 (date-partitioned)
                       Deps: ex_aws ~> 2.5, ex_aws_s3 ~> 2.5, sweet_xml ~> 0.7 (added to mix.exs)
  workers/            12 Oban workers (fetch_lineups, fetch_schedule, fetch_news,
                       generate_predictions, generate_scouting, generate_game_day,
                       generate_player_seo, warm_cache, generate_sitemap, cleanup,
                       parse_setting, run_news_agents)

lib/sports_fanatic_web/
  components/         seo_components.ex — json_ld/2, breadcrumbs/1, subscribe_cta/1, date_nav/1
  controllers/        Page, Player, Team, Lineup, News, Scouting, GameDay, Sitemap,
                       Auth, Subscription, StripeWebhook controllers + HTML modules
  live/               NewsLive — public news feed + agent command input + Feed/Agents tabs +
                         client-side search; subscribes to agent:settings:{user_id} PubSub topic
                       DashboardLive, ScoutingLive, GameDayLive, GameDayIndexLive,
                       ArchiveScoutingLive, ArchiveGameDayLive,
                       AdminLive (+ Agents tab: feature flag, user settings, Run All trigger)
  plugs/              FetchCurrentUser, RequireAuthenticated, RequireAdmin, SubscriptionGate,
                       VerifyStripeWebhook, CacheRawBody
  router.ex           Route definitions — see Routing section below

python_bridge/src/
  api/predict.py      POST /predict/hit, /predict/hr
  api/scouting.py     POST /scouting/search (Exa), /scouting/generate (Claude)
  api/gameday.py      POST /gameday/generate (Claude)
  api/news.py         POST /news/analyze — Claude tool_use classification (category, sentiment, summary,
                       domain_tags)
  api/agents.py       POST /agents/parse-setting, POST /agents/execute (Phase 2 stub)
  agents/__init__.py  Empty module init
  agents/parser.py    parse_setting() — Claude Haiku tool_use parser; returns structured criteria JSON;
                       includes prompt injection guardrails; rejects prompts > 500 chars
  news/analyzer.py    analyze_article() with classify_article tool definition (+ domain_tags output)
  news/models.py      Pydantic models: NewsCategory enum, NewsSentiment enum, NewsAnalysis (+ domain_tags)
  simulation/engine.py  Monte Carlo engine, NumPy-vectorized, 10k trials
  config.py           Settings from environment variables
  main.py             FastAPI app, routers registered (+ agents router), /health endpoint
```

---

## Routing Conventions

```
/                         PageController :home  (renders home.html.heex directly — no redirect)
/mlb/players              PlayerController :index
/mlb/players/:team/:player PlayerController :show
/mlb/teams                TeamController :index
/mlb/teams/:team          TeamController :show
/mlb/lineups/:date        LineupController :show
/mlb/news                 NewsLive :today  (LiveView; renders today's feed inline, URL stays /mlb/news, live updates via PubSub)
/mlb/news/today           NewsController :redirect_today  (302 redirect to /mlb/news/<current ET date>)
/mlb/news/:date           NewsLive :index  (LiveView; live updates via PubSub, patch-based date nav)
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

**NewsLive events** (`handle_event` callbacks added for the agent command input):

| Event | Payload | Auth required | Description |
|-------|---------|---------------|-------------|
| `submit_command` | `%{"input" => text}` | Yes | Parses slash command and dispatches; plain text triggers client-side search |
| `delete_setting` | `%{"id" => setting_id}` | Yes | Deletes the user's agent setting |
| `switch_news_tab` | `%{"tab" => "feed" \| "agents"}` | No | Toggles between Feed and Agents tab (assigns only, no URL change) |
| `search_feed` | `%{"query" => text}` | No | Client-side substring filter on `@feed`; debounced 300ms via `phx-debounce` |
| `run_setting_now` | `%{"id" => setting_id}` | Premium | Enqueues immediate agent execution (premium subscribers only) |

**PubSub topics** used by `NewsLive`:
- `"news:feed:{date}"` — existing; new articles broadcast to all subscribers for a date
- `"news:feed"` — existing; global news broadcast
- `"agent:settings:{user_id}"` — new; `ParseSettingWorker` broadcasts `{:setting_updated, setting}` after LLM parsing completes, so the Agents tab refreshes automatically

**Breadcrumb convention**: MLB-section pages use a four-level breadcrumb: `Home / Baseball / <Section> / <Detail>`. "Baseball" always links to `/mlb/teams`. The same hierarchy appears in both the visible `breadcrumbs/1` component and the JSON-LD `BreadcrumbList` structured data. Example for lineups: `Home → Baseball (/mlb/teams) → Lineups (/mlb/lineups/<today>) → <date>`.

**Lineups nav link**: The Lineups link in the root layout nav (desktop and mobile) is currently commented out. The `/mlb/lineups/:date` route is still fully functional and accessible via direct URL — the nav entry is hidden, not removed.

---

## Date Navigation

News and lineup pages display data-aware previous/next date navigation at the top and bottom of the page.

**Component**: `date_nav/1` in `SportsFanaticWeb.SEOComponents`

```heex
<%# Controller template (full-page navigation) %>
<.date_nav prev_date={@prev_date} next_date={@next_date} base_path="/mlb/news" />

<%# LiveView template (patch navigation — keeps WebSocket alive) %>
<.date_nav prev_date={@prev_date} next_date={@next_date} base_path="/mlb/news" link_type={:patch} />
```

Attributes:
- `prev_date` — `%Date{}` or `nil`. When nil, the prev arrow is suppressed.
- `next_date` — `%Date{}` or `nil`. When nil, the next arrow is suppressed.
- `base_path` — path prefix; links resolve to `{base_path}/{YYYY-MM-DD}`.
- `link_type` — `:href` (default) renders a plain `<a>` tag. `:patch` renders `<.link patch=...>` for LiveView patch navigation that calls `handle_params` without remounting.

**News date lookup** (`SportsFanatic.News`):
- `nearest_news_date_before/1` — MAX aggregate on `news_items.published_date` where date is before the given date.
- `nearest_news_date_after/1` — MIN aggregate on `news_items.published_date` where date is after the given date.
- `next_date` for news is capped at today's Eastern time date — future dates are never linked. `NewsLive` recalculates this cap on every `:tick` so the "next" arrow appears automatically after midnight.

**Lineup date lookup** (private functions in `LineupController`):
- `nearest_lineup_date_before/1` — queries `mlb.lineups` for the nearest preceding date with data.
- `nearest_lineup_date_after/1` — queries `mlb.lineups` for the nearest following date with data.
- No future-date cap for lineups — scheduled games legitimately exist in the future.

News pages (`NewsLive`) and lineup pages (`LineupController`) both assign `@prev_date` and `@next_date` and pass them to `date_nav/1` in the template. News uses `link_type={:patch}`; lineups use the default `:href`.

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
| `accounts` | users, subscriptions, sessions, news_agent_settings, news_agent_results | Auth, billing, and agent settings |
| `system` | pipeline_runs, pipeline_steps, cache_invalidations | Operations |
| `scouting` | (from sports-fan-agent, retained) | |

All UUIDs use `gen_random_uuid()`. `slug` fields follow the pattern `lowercase-hyphenated-name`.

**`accounts.news_agent_settings`** (new): Stores each user's natural language agent task.

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | |
| `user_id` | UUID FK | `accounts.users`, ON DELETE CASCADE |
| `raw_prompt` | TEXT | Original natural language, max 500 chars |
| `parsed_criteria` | JSONB | LLM-structured output; null until parsing completes |
| `status` | VARCHAR(20) | `pending`, `active`, `running`, `completed`, `failed`, `expired` |
| `last_run_at` | TIMESTAMPTZ | |
| `last_result` | JSONB | |
| `error_message` | TEXT | Generic user-safe message only (internal errors are logged) |
| `created_at` / `updated_at` | TIMESTAMPTZ | |

Indexes: `user_id`, `status`.

**`accounts.news_agent_results`** (new): One row per daily agent execution result, per setting.

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | |
| `user_id` | UUID FK | `accounts.users`, ON DELETE CASCADE |
| `setting_id` | UUID FK | `accounts.news_agent_settings`, ON DELETE CASCADE |
| `matched_news_item_ids` | UUID[] | References to `content.news_items` |
| `exa_results` | JSONB | External articles from Exa.ai (Phase 2) |
| `explanation` | TEXT | Human-readable explanation from LLM |
| `run_date` | DATE | |
| `created_at` | TIMESTAMPTZ | |

Indexes: `(user_id, setting_id)`, `run_date`.

**`content.news_items`** (altered): Added `domain_tags TEXT[] DEFAULT '{}'` with a GIN index. Populated by `FetchNewsWorker` from the enhanced `/news/analyze` response. Values are baseball-domain tags such as `"streak"`, `"home-run"`, `"trade-deadline"`, `"walk-off"`, `"no-hitter"`, `"save"`, `"closer"`, `"bullpen"`, `"rotation"`, `"prospect"`, `"call-up"`, `"slump"`.

Migration: `priv/repo/migrations/20260515190000_create_news_agent_tables.exs`

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
sf:data:news:feed:{date}          TTL 60 s  (enriched JSON news feed; invalidated by FetchNewsWorker on new articles)
sf:sitemap:*                      TTL 6 hours
```

Use `SportsFanatic.Cache.get/1`, `put/3`, `delete/1`, `invalidate_pattern/1`.

Key builders: `Cache.news_feed_key/1` accepts a `%Date{}` or ISO-8601 string.

Agent settings and results are not cached in Valkey — they are read directly from PostgreSQL per user on each LiveView mount and on `agent:settings:{user_id}` PubSub messages.

---

## Python Bridge

`SportsFanatic.PythonBridge` is the Elixir-side HTTP client. It calls `http://python-bridge:8000` (Docker internal) via `Req`. The circuit breaker (`SportsFanatic.PythonBridge.CircuitBreaker`) trips after 3 consecutive failures and stays open for 5 minutes. `SportsFanatic.PythonBridge.HealthCheck` pings `/health` every 30 seconds.

Available endpoints (called via `PythonBridge.*` functions):
- `POST /predict/hit`, `POST /predict/hr` — ML game predictions
- `POST /scouting/search`, `POST /scouting/generate` — AI scouting reports
- `POST /gameday/generate` — AI Game Day Magazine generation
- `POST /news/analyze` — Claude tool_use classification; returns `{category, sentiment, summary, domain_tags}` for a news headline + excerpt. Called by `FetchNewsWorker` via `PythonBridge.analyze_news/2`. If the circuit breaker is open, articles are stored with `ai_processed: false` for later backfill.
- `POST /agents/parse-setting` — Claude Haiku tool_use parser; accepts `{raw_prompt, context}` and returns structured criteria including `target_players`, `target_teams`, `target_leagues`, `stat_filters`, `categories`, `domain_tags`, `requires_exa_search`, `exa_query`, `confidence`, `interpretation`. Called by `ParseSettingWorker` via `PythonBridge.parse_setting/2`. Rejects prompts over 500 characters. Includes prompt injection guardrails in the system prompt.
- `POST /agents/execute` — Phase 2 stub; currently returns empty results. Will support Exa.ai search and batched user execution in Phase 2. Called by `RunNewsAgentsWorker` via `PythonBridge.execute_agents/2`.

In production, the `python-bridge` service should not expose port 8000 to the host. The `docker-compose.yml` currently exposes it — remove the `ports` entry for production (SEC-007).

---

## Oban Workers

All workers live in `lib/sports_fanatic/workers/`. They use `use Oban.Worker, queue: :default, max_attempts: 3`.

Cron schedules are defined in `config/config.exs` under `Oban.crontab`. Times are UTC (convert from ET accordingly).

Scheduled cron entries:
- `FetchNewsWorker` — every 1 minute (`* * * * *`). Uses `unique: [period: 55]` to prevent overlap. Most runs are no-ops when no new articles are found.
- `GeneratePlayerSeoWorker` — 4:00 AM UTC daily
- `GeneratePredictionsWorker` — 9:30 AM UTC daily
- `WarmCacheWorker` — every 15 minutes
- `RunNewsAgentsWorker` — `0 13 * * *` (9:00 AM ET during EDT = 13:00 UTC). Gated by `news_agents_enabled` feature flag. Processes each user with active settings sequentially; failures for one user do not block others. Schedule override is configurable via the Joshua admin Agents tab.

Non-scheduled workers (enqueued on demand):
- `ParseSettingWorker` — enqueued by `Agents.create_setting/2` immediately after INSERT. Calls `/agents/parse-setting` on the Python Bridge and updates the setting's `parsed_criteria` and `status`. Broadcasts `{:setting_updated, setting}` on `"agent:settings:{user_id}"` PubSub on completion. Error messages stored are generic (internal error details are logged via `Logger.error`).

To manually enqueue a worker in IEx:
```elixir
%{} |> SportsFanatic.Workers.FetchLineupsWorker.new() |> Oban.insert()
%{} |> SportsFanatic.Workers.RunNewsAgentsWorker.new() |> Oban.insert()
%{"setting_id" => "uuid"} |> SportsFanatic.Workers.ParseSettingWorker.new() |> Oban.insert()
```

---

## Testing Strategy

- **Pure unit tests** (`mix test.unit`): Schema changesets, `Slug.slugify/1`, `has_active_subscription?/1`, cache key builders, circuit breaker state machine, `date_nav/1` component (84 tests total). No PostgreSQL required.
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
| AGENTS-001 | LOW | `RunNewsAgentsWorker` matches players/teams via ILIKE text search on `parsed_criteria` JSON values. Phase 2 should resolve to `player_ids`/`team_ids` via `EntityMatcher` for accurate matching. |
| AGENTS-002 | LOW | `POST /agents/execute` on the Python Bridge is a stub returning empty results. Phase 2 activates Exa.ai search and batched multi-user execution. |
| AGENTS-003 | LOW | Domain tags are not backfilled for news articles classified before the `domain_tags` column was added. A one-shot backfill worker should be run post-deployment to re-classify those articles. |

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

**Enable/disable agent execution:**
- Toggle `news_agents_enabled` via the Joshua admin Agents tab at `/admin`.
- Or set it directly in IEx: the flag is checked at runtime in `RunNewsAgentsWorker` before any DB queries.

**Manually run agents for all users:**
```elixir
# IEx
%{} |> SportsFanatic.Workers.RunNewsAgentsWorker.new() |> Oban.insert()
```

**Add a new agent skill (Phase 2):**
1. Add `{:jido, "~> 2.2"}` to `mix.exs` (currently omitted — Phase 2 only).
2. Create a skill module under `lib/sports_fanatic/agents/skills/`.
3. Register the skill in `SportsFanatic.Agents.NewsAgent`.
4. Add corresponding Python Bridge endpoint if external tool use is required.

**Backfill domain_tags for existing articles:**
```elixir
# Enqueue a one-shot backfill — implement as a temporary Oban worker that queries
# news_items WHERE domain_tags = '{}' and re-calls PythonBridge.analyze_news/2
```

---

## Database Backup & Restore

Scripts live in `scripts/`. Local backups land in `backups/` (gitignored). Run any script with `-h` for full flag reference.

**Quick reference:**

```bash
# Local backup only
./scripts/db_backup.sh

# Backup and upload to S3
S3_BUCKET=my-bucket ./scripts/db_backup.sh

# Backup specific schemas only
./scripts/db_backup.sh --schemas public,mlb,content

# Backup without S3 upload even when S3_BUCKET is set
./scripts/db_backup.sh --no-s3

# Restore from local file (prompts for confirmation)
./scripts/db_restore.sh backups/sports_fanatic_20260426_090000.dump

# Restore from local file — skip prompt
./scripts/db_restore.sh backups/sports_fanatic_20260426_090000.dump --force

# Restore from S3 URI with clean DB (drop + recreate + init.sql + restore)
./scripts/db_restore.sh s3://my-bucket/backups/sports-fanatic/sports_fanatic_20260426_090000.dump --force --drop

# Parallel restore (faster for large databases)
./scripts/db_restore.sh backups/sports_fanatic_20260426_090000.dump --force --jobs 4

# List backups in S3
S3_BUCKET=my-bucket ./scripts/db_s3_sync.sh list

# Upload a file manually
S3_BUCKET=my-bucket ./scripts/db_s3_sync.sh upload backups/sports_fanatic_20260426_090000.dump

# Download a backup from S3
S3_BUCKET=my-bucket ./scripts/db_s3_sync.sh download sports_fanatic_20260426_090000.dump

# Mix task wrappers (run from project root)
mix db.backup
mix db.restore backups/sports_fanatic_20260426_090000.dump
```

**News S3 environment variables:**

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `NEWS_S3_BUCKET` | S3 bucket for raw news article JSON storage | `sports-fanatic-news` | Only when S3 enabled |
| `NEWS_S3_ENABLED` | Set to `"false"` to skip S3 uploads (e.g., local dev without MinIO) | `"true"` | No |
| `AWS_REGION` | AWS region for ExAws | `us-east-1` | No |
| `AWS_ACCESS_KEY_ID` | AWS credentials for ExAws | — | Yes (or IAM role) |
| `AWS_SECRET_ACCESS_KEY` | AWS credentials for ExAws | — | Yes (or IAM role) |

Raw articles are stored at `news/raw/{YYYY}/{MM}/{DD}/{external_id}.json`. The `external_id` is sanitized (only `[a-zA-Z0-9_-]` allowed) before use in the S3 key to prevent path traversal. The S3 bucket must not be publicly accessible — raw content is served through the application layer only. If S3 upload fails, the article is still stored in PostgreSQL (`s3_key` will be `nil`).

---

**Database Backup & Restore environment variables:**

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `PGHOST` | Database host (auto-detects Docker `db` or `localhost`) | auto | No |
| `PGPORT` | Database port | `5432` | No |
| `PGUSER` | Database user | `postgres` | No |
| `PGPASSWORD` | Database password | `postgres` | No |
| `PGDATABASE` | Database name | `sports_fanatic` | No |
| `BACKUP_DIR` | Directory for local backup files | `./backups` | No |
| `BACKUP_RETENTION_DAYS` | Days to keep local backups before cleanup | `30` | No |
| `S3_BUCKET` | S3 bucket name for remote backups | — | Only for S3 ops |
| `S3_PREFIX` | S3 key prefix | `backups/sports-fanatic` | No |
| `AWS_PROFILE` | AWS CLI named profile | — | No |
| `AWS_REGION` | AWS region | `us-east-1` | No |

Variables can also be set in `.env` at the project root — the scripts source it automatically if present.

**Docker usage:**

```bash
# From host (PostgreSQL port must be exposed — default docker-compose.yml exposes 5432)
PGHOST=localhost ./scripts/db_backup.sh

# Inside the web container (connects to the 'db' service on the internal network)
docker compose exec web ./scripts/db_backup.sh

# S3 credentials available inside the container via environment
docker compose exec -e S3_BUCKET=my-bucket -e AWS_REGION=us-east-1 web ./scripts/db_backup.sh
```
