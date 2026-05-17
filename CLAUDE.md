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
mix test.unit           # 545 pure unit tests, no database required
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

## Agentic Chatbot System

An LLM-powered conversational agent replaces the search textarea on the news feed when the `news_chatbot_enabled` feature flag is on. Users type natural language queries; the agent searches local news, discovers new articles via Exa.ai, classifies and stores them through the existing news pipeline, and streams real-time progress back to the LiveView. When the flag is off, the UI falls back to the legacy textarea/command mode exactly as before.

### Feature Flag

`news_chatbot_enabled` — toggled via the Joshua admin Agents tab at `/admin`. When disabled, legacy textarea and `/settings-apply` commands are preserved unchanged.

### Chat UI (NewsLive)

When the chatbot is enabled, the textarea is replaced by a scrollable chat thread + input row. The chat container uses `phx-update="append"` (LiveView 0.19 compatible — no `streams`). A `ScrollBottom` LiveView hook in `assets/js/app.js` auto-scrolls the container on new messages.

Unauthenticated users see the input but receive a login prompt on submit. Authenticated users get up to 10 queries/hour and 50/day (enforced by `ChatBot` context). At most 1 active agent runs per user — submitting a new query cancels any in-flight agent.

**LiveView events** (chat mode):

| Event | Payload | Auth required | Description |
|-------|---------|---------------|-------------|
| `submit_chat` | `%{"message" => text}` | Yes | Submit a chat message and spawn the agent |
| `clear_chat` | `%{}` | Yes | Clear chat history for current session |
| `cancel_agent` | `%{}` | Yes | Cancel a running agent process |

**PubSub topics** added for chat:
- `"chat:agent:{user_id}"` — agent broadcasts `{:agent_progress, msg}`, `{:agent_complete, summary, ids}`, `{:agent_error, text}` during execution

### Agent Architecture

**Important**: `jido` v2.2 and `jido_ai` v2.1 require Elixir >= 1.18. The project runs Elixir 1.15.7 — these deps are incompatible and were not added. Instead, a lightweight `SportsFanatic.Agents.Action` behaviour (`lib/sports_fanatic/agents/action.ex`) provides the same interface (`name/0`, `description/0`, `run/2`) used by all action modules. The `NewsAgent` orchestrator implements its own ReAct-style tool loop without the Jido runtime.

**Agent modules:**

| Module | File | Purpose |
|--------|------|---------|
| `SportsFanatic.Agents.Action` | `agents/action.ex` | Behaviour defining the action interface (Jido-compatible without the dep) |
| `SportsFanatic.Agents.NewsAgent` | `agents/news_agent.ex` | Orchestrator — ReAct tool loop, PubSub progress, session storage |
| `SportsFanatic.Agents.AgentSupervisor` | `agents/agent_supervisor.ex` | `DynamicSupervisor` + `Registry` for per-user agent processes |
| `Actions.SearchLocalNews` | `agents/actions/search_local_news.ex` | Full-text search on `news_items` via `tsvector` |
| `Actions.SearchExa` | `agents/actions/search_exa.ex` | Exa.ai web search with URL dedup against existing `news_items` |
| `Actions.ResolveEntities` | `agents/actions/resolve_entities.ex` | Player/team entity matching via `EntityMatcher` |
| `Actions.ClassifyArticle` | `agents/actions/classify_article.ex` | AI classify via Python Bridge, entity resolve, store, cache invalidate, PubSub broadcast |

`AgentSupervisor` registers each process via `{:via, Registry, {AgentRegistry, user_id}}`. Processes self-terminate after completion or a 60-second timeout. Both `AgentRegistry` and `AgentDynamicSupervisor` are added to the application supervision tree in `application.ex`.

### Exa.ai Client

`SportsFanatic.ExternalApis.Exa` (`lib/sports_fanatic/external_apis/exa.ex`) calls the Exa REST API directly using `Req` — independent of the Python Bridge. This keeps the chatbot's article discovery path separate from the scouting use case. Only `http`/`https` URLs from Exa results are accepted before storage (CHAT-SEC-006). Configured via `EXA_API_KEY` in `runtime.exs`.

The Python Bridge's existing `/scouting/search` Exa endpoint is unchanged and continues to serve the scouting feature.

### Article Discovery Pipeline

When `SearchExa` finds external articles whose URLs are not already in `content.news_items`, `ClassifyArticle` runs each through the full pipeline:
1. `POST /news/analyze` on the Python Bridge (classification, sentiment, domain tags)
2. `EntityMatcher` for player/team resolution
3. INSERT into `content.news_items` with `source: "exa"`
4. Valkey cache invalidation + `news:feed:{date}` PubSub broadcast

Discovered articles become part of the global news feed for all users immediately. Deduplication uses a partial unique index on `(source_url) WHERE source = 'exa'`.

### Chat History

Chat history is stored in the `accounts` schema. Sessions expire after 30 minutes of inactivity; new sessions start automatically. The last 10 messages (5 user + 5 assistant) are sent to the LLM as context for follow-up queries.

`SportsFanatic.ChatBot` (`lib/sports_fanatic/chat_bot.ex`) is the context module: session CRUD, rate limiting, cluster management.

### Query Clusters and Consolidation

All user chat queries are clustered by entity overlap + keyword similarity. Clusters are stored in `accounts.query_clusters`. `ConsolidateQueriesWorker` runs hourly to re-cluster. Admin can mark a cluster as "scheduled" (daily or hourly) to run automatic Exa searches via `ScheduledExaSearchWorker`.

### Joshua Admin Queries Tab

`/admin` includes a "Queries" tab (in addition to the existing Agents tab) with:
- All unique user query clusters with entity tags, topic tags, and frequency counts
- Per-cluster toggle to enable/disable as a scheduled Exa search
- Per-cluster frequency selector (hourly/daily/disabled)
- "Run Now" button per cluster (enqueues `ScheduledExaSearchWorker` on demand)
- Chat session browser (admin sees all users' sessions)
- Chatbot enable/disable toggle (`news_chatbot_enabled` flag)

**AdminLive events** (Queries tab):

| Event | Payload | Description |
|-------|---------|-------------|
| `switch_tab` (tab: "queries") | — | Load query clusters |
| `toggle_query_schedule` | `%{"cluster_id" => uuid}` | Toggle scheduled flag |
| `set_query_frequency` | `%{"cluster_id" => uuid, "freq" => string}` | Set hourly/daily/disabled |
| `run_query_now` | `%{"cluster_id" => uuid}` | Enqueue immediate Exa search |

---

## News Feed Settings (Legacy Agent System)

An LLM-powered agent system lets authenticated users define natural language "settings" (agent tasks) via a sticky command input box on the news feed. Settings are parsed by Claude Haiku into structured search/filter criteria, executed daily at 9am ET, and displayed in an "Agents" tab alongside the existing news feed.

This system coexists with the chatbot. When `news_chatbot_enabled` is off, the command input and Agents tab are the primary user-facing agent feature.

### Command Input

The command input is a sticky `<textarea>` rendered at the top of `NewsLive` on `/mlb/news`, `/mlb/news/:date`, and `/`. The input is always enabled for all users — unauthenticated users can search the feed; slash commands (`/settings-*`) require login and show a flash error if attempted without auth. Commands:

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

## Hit Predictions Pipeline

A daily Elixir-native pipeline that seeds hitter and pitcher data, computes 44-column feature vectors per player, scores them via a GradientBoosting model in the Python bridge, and persists per-player hit probabilities to `mlb.hit_predictions`. Results are surfaced on a new public `/predictions` LiveView and as a "Today's Hit Prediction" banner on player detail and scouting report pages.

**Data flow (daily, 8:00 AM ET):**

```
Oban Cron (0 12 * * * UTC)
  → DailyHitPredictionsWorker (orchestrator)
      ├── FetchScheduleWorker     → MLB Stats API → mlb.scheduled_games
      ├── FetchLineupsWorker      → FantasyNerds  → mlb.lineups
      ├── SeedPitcherHistoryWorker → MLB Stats API → mlb.pitcher_game_logs
      ├── SeedStatcastWorker      → Baseball Savant CSV → mlb.player_statcast
      ├── FetchPitcherStatsWorker → MLB Stats API → mlb.pitcher_stats
      ├── FetchBvPWorker          → MLB Stats API → mlb.batter_vs_pitcher
      ├── ForecastWeatherWorker   → Open-Meteo API → mlb.game_weather_forecast
      └── PredictHitsWorker
            ├── Features.build_inference_row/3 (44 columns per player)
            ├── POST /inference/hit → Python bridge (GBT fit+predict)
            ├── Repo.insert_all mlb.hit_predictions (ON CONFLICT upsert)
            ├── Valkey DEL sf:page:player:*, sf:data:hit_prediction:*, sf:data:predictions:*
            └── PubSub broadcast "predictions:hits:{date}" → PredictionsLive re-renders
```

### Feature Flag

`hit_predictions_enabled` — toggled via the Joshua admin Predictions tab at `/admin`. When disabled, `DailyHitPredictionsWorker` returns `:ok` immediately without writing any rows.

### Cron

Default cron: `0 12 * * *` (8:00 AM EDT = 12:00 UTC). For winter operation override to `0 13 * * *` via `PREDICTIONS_CRON_OVERRIDE`. Loaded from env at startup in `config/runtime.exs`; no rebuild required.

### New Elixir Modules

| Module | File | Purpose |
|--------|------|---------|
| `SportsFanatic.Predictions` | `predictions.ex` | Context API: `list_for_date/2`, `get_for_player/2`, `list_today/1`, `list_runs/1`, `run_now/1`, `stream_player_results/1` |
| `SportsFanatic.Predictions.HitPrediction` | `predictions/hit_prediction.ex` | Ecto schema for `mlb.hit_predictions`; `tier_for_prob/1` (S/A/B/C/D) |
| `SportsFanatic.Predictions.FeatureLoader` | `predictions/feature_loader.ex` | SQL aggregations for training and inference data |
| `SportsFanatic.Predictions.Features` | `predictions/features.ex` | 44-column feature row builder; `feature_cols/0`; `build_inference_row/3`; `build_training_rows/2` |
| `SportsFanatic.Predictions.Inference` | `predictions/inference.ex` | HTTP client to `POST /inference/hit`; uses existing circuit breaker |
| `SportsFanatic.Predictions.ParkFactors` | `predictions/park_factors.ex` | Static `DEFAULT_PARK_HIT_FACTORS` table + DB lookup; `hit_factor_static/1` returns 1.0 for unknown venues |
| `SportsFanatic.Predictions.Stadiums` | `predictions/stadiums.ex` | Venue-ID → lat/lon map (port of `stadiums.py`) |
| `SportsFanatic.Mlb.PitcherGameLog` | `mlb/pitcher_game_log.ex` | Ecto schema for `mlb.pitcher_game_logs` |
| `SportsFanatic.Mlb.PlayerStatcast` | `mlb/player_statcast.ex` | Ecto schema for `mlb.player_statcast` |
| `SportsFanatic.ExternalApis.MlbStats` | `external_apis/mlb_stats.ex` | MLB Stats API client via `Req`: `fetch_schedule/1`, `fetch_boxscore/1`, `fetch_pitcher_season_stats/2`, `fetch_player_statcast/2`, `fetch_batter_vs_pitcher/3`, `lookup_player/1` |
| `SportsFanatic.ExternalApis.OpenMeteo` | `external_apis/open_meteo.ex` | Open-Meteo forecast + archive client; `extract_at_game_time/2` |
| `SportsFanaticWeb.PredictionsLive` | `live/predictions_live.ex` | `/predictions` LiveView; sorted by `hit_prob` desc; team/league/batting-order filters; re-renders on `{:hits_ready, date}` PubSub |
| `SportsFanaticWeb.PredictionComponents` | `components/prediction_components.ex` | `today_hit_banner/1` component rendered on player detail + scouting pages |
| `SportsFanaticWeb.PredictionsRedirectController` | `controllers/predictions_redirect_controller.ex` | Issues 301 redirect from `/mlb/players` to `/predictions` |

### New Workers

All use `queue: :predictions, max_attempts: 3`. The orchestrator (`DailyHitPredictionsWorker`) calls the other workers' `perform/1` functions directly (sequentially) to ensure ordered execution. Step parallelism is via `Task.async_stream` inside each worker.

| Worker | File | Purpose |
|--------|------|---------|
| `DailyHitPredictionsWorker` | `workers/daily_hit_predictions_worker.ex` | Cron orchestrator; opens `system.pipeline_runs` row; sequences all steps |
| `FetchPitcherStatsWorker` | `workers/fetch_pitcher_stats_worker.ex` | Upserts probable-pitcher season stats into `mlb.pitcher_stats` |
| `FetchBvPWorker` | `workers/fetch_bvp_worker.ex` | Upserts batter-vs-pitcher records into `mlb.batter_vs_pitcher` |
| `SeedPitcherHistoryWorker` | `workers/seed_pitcher_history_worker.ex` | Backfills `mlb.pitcher_game_logs` for the last 30 days |
| `SeedStatcastWorker` | `workers/seed_statcast_worker.ex` | Upserts Statcast aggregates into `mlb.player_statcast` via Baseball Savant CSV |
| `ForecastWeatherWorker` | `workers/forecast_weather_worker.ex` | Upserts game-time weather into `mlb.game_weather_forecast` via Open-Meteo |
| `PredictHitsWorker` | `workers/predict_hits_worker.ex` | Builds features, calls `/inference/hit`, upserts `mlb.hit_predictions`, invalidates cache, broadcasts PubSub |

### New Routes

- `/predictions` — `PredictionsLive` (LiveView, public). Today's predictions sorted by hit % desc.
- `GET /mlb/players` — 301 redirect to `/predictions` via `PredictionsRedirectController`. (Player detail `/mlb/players/:team/:player` is unchanged.)

### Scouting + Player Detail Banner

`PlayerController.show/2` and `ScoutingController.show/2` both assign `@today_hit_prediction` via `Predictions.get_for_player(player_mlb_id, today)`. The `<.today_hit_banner prediction={@today_hit_prediction} />` component renders hit %, matchup (Team vs OppTeam), local game time, probable opposing pitcher, and a weather one-liner. When the player has no game today the banner shows "No game today."

### Admin Predictions Tab

`/admin` gains a "Predictions" tab with: feature flag toggle (`hit_predictions_enabled`), run history table (last 30 runs of type `hit_predict_daily` from `system.pipeline_runs`), per-run drill-down of all `mlb.hit_predictions` for that run, and a "Run Now" button.

**Deferred** (env vars are the source of truth): cron-override input field and concurrency-override input field — those are set via `PREDICTIONS_CRON_OVERRIDE` and the concurrency env vars rather than the admin UI.

**AdminLive events** (Predictions tab):

| Event | Payload | Description |
|-------|---------|-------------|
| `switch_tab` (tab: "predictions") | — | Load run history + flag value |
| `toggle_predictions_flag` | `%{"enabled" => bool}` | Toggle `hit_predictions_enabled` in `feature_flags` table |
| `run_predictions_now` | `%{"date" => iso}` | Enqueue `DailyHitPredictionsWorker` with `force: true` |
| `view_run` | `%{"run_id" => uuid}` | Drill-down into per-player results for a run |

### Python Bridge Changes

**Added**: `POST /inference/hit` (`python_bridge/src/api/inference.py`) — fits a `GradientBoostingClassifier` on the supplied training rows and predicts on inference rows. Response: `{model_version, training_metrics, predictions: [{player_mlb_id, hit_prob, prediction}]}`.

**Deleted**: `python_bridge/src/api/predict.py` (`/predict/hit`, `/predict/hr`), `python_bridge/src/api/schedule.py`, `python_bridge/src/simulation/` (entire directory). `/agents/execute` route removed from `api/agents.py`.

**Kept** (still called by legacy scouting pipeline): `search_player_multi/1`, `classify_content/2` on the Elixir bridge; `/scouting/search`, `/scouting/generate`, `/news/analyze`, `/gameday/generate`, `/agents/parse-setting` on the Python side.

### Tunable Concurrency

All values are read from `Application.get_env(:sports_fanatic, :predictions)` at runtime (set in `config/runtime.exs`). Changing env vars and restarting applies immediately; no recompile needed.

| Env Var | Default | Controls |
|---------|---------|---------|
| `PREDICTIONS_CONCURRENCY` | `8` | Default for steps without a step-specific override |
| `PREDICTIONS_CRON_OVERRIDE` | `0 12 * * *` | Oban cron expression for `DailyHitPredictionsWorker` |
| `PREDICTIONS_PITCHER_STATS_CONCURRENCY` | `4` | `FetchPitcherStatsWorker` `Task.async_stream` concurrency |
| `PREDICTIONS_BVP_CONCURRENCY` | `6` | `FetchBvPWorker` `Task.async_stream` concurrency |
| `PREDICTIONS_STATCAST_CONCURRENCY` | `4` | `SeedStatcastWorker` `Task.async_stream` concurrency |
| `PREDICTIONS_SEED_PITCHER_CONCURRENCY` | `4` | `SeedPitcherHistoryWorker` `Task.async_stream` concurrency |
| `PREDICTIONS_WEATHER_CONCURRENCY` | `8` | `ForecastWeatherWorker` `Task.async_stream` concurrency |
| `PREDICTIONS_FEATURE_COMPUTE_CONCURRENCY` | `16` | `PredictHitsWorker` per-player feature computation concurrency |
| `OPENMETEO_API_KEY` | _(blank)_ | Optional — Open-Meteo free tier requires no key |

---

## Architecture Summary

```
Browser → Phoenix Router
           ├── /mlb/news, /mlb/news/:date → NewsLive (LiveView, WebSocket)
           │     ├── (connected) subscribes to Phoenix PubSub "news:feed:{date}" + "news:feed"
           │     │                                              + "agent:settings:{user_id}"
           │     │                                              + "chat:agent:{user_id}"  (chatbot mode)
           │     └── reads Valkey cache → (miss) → PostgreSQL
           ├── /mlb/news/today → NewsController :redirect_today → 302 /mlb/news/<current ET date>
           ├── /mlb/* → SEO Controllers → (Valkey cache hit) → HTML response
           │                            → (cache miss) → PostgreSQL → render → cache → HTML
           ├── /premium/* → LiveView (subscription-gated, WebSocket)
           └── /webhooks/stripe → StripeWebhookController

Agentic Chatbot (news_chatbot_enabled flag)
  NewsLive submit_chat → ChatBot.create_message/2 → AgentSupervisor.start_agent/2
                       → NewsAgent (ReAct loop via DynamicSupervisor)
                           ├── Actions.SearchLocalNews → PostgreSQL tsvector search
                           ├── Actions.SearchExa → ExternalApis.Exa (Req) → Exa.ai API
                           │     └── new URLs → Actions.ClassifyArticle
                           │                     → Python Bridge /news/analyze
                           │                     → EntityMatcher → PostgreSQL INSERT
                           │                     → Valkey invalidate → PubSub news:feed broadcast
                           ├── Actions.ResolveEntities → EntityMatcher
                           └── PubSub chat:agent:{user_id} → :agent_progress / :agent_complete / :agent_error

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
  ConsolidateQueriesWorker (hourly) → ChatBot context → entity+keyword clustering → PostgreSQL
  ScheduledExaSearchWorker (per cluster) → ExternalApis.Exa → classify + store new articles
  DailyHitPredictionsWorker (daily 8am ET) → FetchScheduleWorker → FetchLineupsWorker
                                           → SeedPitcherHistoryWorker → SeedStatcastWorker
                                           → FetchPitcherStatsWorker → FetchBvPWorker
                                           → ForecastWeatherWorker → PredictHitsWorker
                                           → POST /inference/hit (Python GBT) → mlb.hit_predictions
                                           → Valkey invalidate → PubSub "predictions:hits:{date}"
                                           → PredictionsLive re-renders
  GenerateScouting / GenerateGameDay → Python Bridge → Claude API → PostgreSQL
  WarmCache → Valkey
  GenerateSitemap → PostgreSQL

Python Bridge (python_bridge/ → Docker service on internal network, expose: only — not host-bound)
  FastAPI + GradientBoosting ML model (inference only via /inference/hit)
  Calls: Claude API, Exa AI search (scouting only)
  Deleted: /predict/hit, /predict/hr, /schedule/*, /simulation/*, /agents/execute
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
                       action.ex — Action behaviour (name/0, description/0, run/2); Jido-compatible
                         interface implemented in plain Elixir (jido dep incompatible with Elixir 1.15)
                       news_agent.ex — orchestrator; ReAct-style tool loop; broadcasts PubSub progress
                       agent_supervisor.ex — DynamicSupervisor + Registry; per-user agent processes
                       actions/search_local_news.ex — tsvector full-text search on news_items
                       actions/search_exa.ex — Exa.ai web search with URL dedup
                       actions/resolve_entities.ex — player/team entity matching via EntityMatcher
                       actions/classify_article.ex — AI classify, store, cache invalidate, PubSub broadcast
  billing/            Subscription schema
  billing.ex          Stripe webhook handlers (checkout, invoice, subscription events)
  cache.ex            Valkey wrapper — get/set/delete/invalidate_pattern + TTL constants
  chat_bot.ex         ChatBot context — session CRUD, rate limiting (10/hr, 50/day), cluster management
  chat_bot/           chat_session.ex — Ecto schema (accounts.chat_sessions)
                       chat_message.ex — Ecto schema (accounts.chat_messages; role: user|assistant|progress)
                       query_cluster.ex — Ecto schema (accounts.query_clusters)
                       query_cluster_member.ex — Ecto schema (accounts.query_cluster_members)
  content/            ScoutingReport, GameDayMagazine, NewsItem (+ domain_tags, + search_vector tsvector),
                       Sitemap schemas
  external_apis/      FantasyNerds HTTP client
                       exa.ex — direct Exa.ai HTTP client via Req (chatbot discovery path)
                       mlb_stats.ex — MLB Stats API client via Req (schedule, boxscore, season stats, statcast, BvP)
                       open_meteo.ex — Open-Meteo forecast + archive client; extract_at_game_time/2
  mlb/                Sport, Team, Player, Venue, Game, ScheduledGame, Lineup, Pick, HrPick,
                       PitcherGameLog (mlb.pitcher_game_logs), PlayerStatcast (mlb.player_statcast)
  news.ex             News context — cached feed reads, entity-resolved list, get_cached_feed/1,
                       nearest_news_date_before/1, nearest_news_date_after/1, exists_by_source_url?/1
                       Feed data includes domain_tags and team.league for badge display
  news/               entity_matcher.ex — fuzzy player/team matching (jaro_distance, threshold 0.85)
  python_bridge.ex    HTTP client for Python bridge with circuit breaker integration
                       Added: parse_setting/2, execute_agents/2
  python_bridge/      CircuitBreaker GenServer + HealthCheck GenServer
  storage.ex          S3 storage module — put_object/3, get_object/2, news_article_key/2 (date-partitioned)
                       Deps: ex_aws ~> 2.5, ex_aws_s3 ~> 2.5, sweet_xml ~> 0.7 (added to mix.exs)
  workers/            21 Oban workers:
                       fetch_lineups (modified — accepts date arg, removed auto-chain),
                       fetch_schedule (modified — uses MlbStats Elixir client),
                       fetch_news, generate_predictions (delegates to DailyHitPredictionsWorker),
                       generate_scouting, generate_game_day, generate_player_seo,
                       warm_cache, generate_sitemap, cleanup,
                       parse_setting, run_news_agents,
                       consolidate_queries, scheduled_exa_search,
                       daily_hit_predictions (orchestrator, queue: predictions),
                       fetch_pitcher_stats, fetch_bvp, seed_pitcher_history,
                       seed_statcast, forecast_weather, predict_hits
  predictions/        hit_prediction.ex — Ecto schema (mlb.hit_predictions); tier_for_prob/1
                       feature_loader.ex — SQL aggregations for training/inference data
                       features.ex — 44-column feature row builder; feature_cols/0
                       inference.ex — HTTP client to POST /inference/hit; uses circuit breaker
                       park_factors.ex — static park hit factors + DB lookup; 1.0 for unknown venues
                       stadiums.ex — venue-ID → lat/lon map
  predictions.ex      Predictions context — list_for_date/2, get_for_player/2, list_today/1,
                       list_runs/1, run_now/1, stream_player_results/1; cache TTL 5 min

lib/sports_fanatic_web/
  components/         seo_components.ex — json_ld/2, breadcrumbs/1, subscribe_cta/1, date_nav/1
  controllers/        Page, Player (assigns today_hit_prediction), Team, Lineup, News,
                       Scouting (assigns today_hit_prediction), GameDay, Sitemap,
                       Auth, Subscription, StripeWebhook, PredictionsRedirect controllers + HTML modules
  live/               NewsLive — chat mode (news_chatbot_enabled) OR legacy command mode;
                         subscribes to agent:settings:{user_id} and chat:agent:{user_id} PubSub topics
                       PredictionsLive — /predictions; sorted by hit_prob desc; subscribes to
                         PubSub "predictions:hits:{date}" for live re-render
                       DashboardLive, ScoutingLive, GameDayLive, GameDayIndexLive,
                       ArchiveScoutingLive, ArchiveGameDayLive,
                       AdminLive (+ Agents tab: settings flag, Run All; + Queries tab: clusters,
                         schedules, chatbot flag, session browser; + Predictions tab: flag toggle,
                         Run Now, run history, per-run drill-down)
  plugs/              FetchCurrentUser, RequireAuthenticated, RequireAdmin, SubscriptionGate,
                       VerifyStripeWebhook, CacheRawBody
  router.ex           Route definitions — see Routing section below

python_bridge/src/
  api/inference.py    POST /inference/hit — GradientBoostingClassifier fit+predict; accepts
                       {training_rows, inference_rows}; returns {model_version, training_metrics, predictions}
  api/scouting.py     POST /scouting/search (Exa), /scouting/generate (Claude)
  api/gameday.py      POST /gameday/generate (Claude)
  api/news.py         POST /news/analyze — Claude tool_use classification (category, sentiment, summary,
                       domain_tags)
  api/agents.py       POST /agents/parse-setting (Claude Haiku) — /agents/execute stub DELETED
  agents/__init__.py  Empty module init
  agents/parser.py    parse_setting() — Claude Haiku tool_use parser; returns structured criteria JSON;
                       includes prompt injection guardrails; rejects prompts > 500 chars
  news/analyzer.py    analyze_article() with classify_article tool definition (+ domain_tags output)
  news/models.py      Pydantic models: NewsCategory enum, NewsSentiment enum, NewsAnalysis (+ domain_tags)
  config.py           Settings from environment variables
  main.py             FastAPI app, routers registered, /health endpoint
  DELETED: api/predict.py, api/schedule.py, simulation/ (entire directory)
```

---

## Routing Conventions

```
/                         PageController :home  (renders home.html.heex directly — no redirect)
/predictions              PredictionsLive :index  (LiveView; today's hit predictions sorted by hit_prob desc;
                            re-renders on PubSub "predictions:hits:{date}")
/mlb/players              PredictionsRedirectController → 301 /predictions
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
| `mlb` | games, scheduled_games, lineups, player_boxscores, player_season_stats, picks, hr_picks, game_weather, park_hr_factors, hit_predictions, pitcher_game_logs, player_statcast, batter_vs_pitcher, game_weather_forecast | Game data and predictions |
| `content` | scouting_reports, game_day_magazines, news_items, sitemaps | AI-generated content |
| `accounts` | users, subscriptions, sessions, news_agent_settings, news_agent_results, chat_sessions, chat_messages, query_clusters, query_cluster_members | Auth, billing, agent settings, and chat |
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

Also added `search_vector tsvector GENERATED ALWAYS AS (...)` with a GIN index for agent full-text search. Weighted: `title` (A), `ai_summary` (B), `body` (C). A partial unique index on `(source_url) WHERE source = 'exa' AND source_url IS NOT NULL` enforces Exa deduplication.

**`accounts.chat_sessions`** (new): Groups related messages for one user.

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | |
| `user_id` | UUID FK | `accounts.users`, ON DELETE CASCADE |
| `status` | VARCHAR(20) | `active`, `expired` |
| `last_activity_at` | TIMESTAMPTZ | Updated on each message; sessions expire after 30 min |
| `inserted_at` | TIMESTAMPTZ | |

Indexes: `user_id`, `last_activity_at`.

**`accounts.chat_messages`** (new): Individual messages within a session.

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | |
| `session_id` | UUID FK | `accounts.chat_sessions`, ON DELETE CASCADE |
| `role` | VARCHAR(20) | `user`, `assistant`, `progress` |
| `content` | TEXT | HTML-sanitized before rendering (`html_sanitize_ex`) |
| `metadata` | JSONB | Tool calls, timing, step info |
| `news_item_ids` | UUID[] | References to matched `content.news_items` |
| `inserted_at` | TIMESTAMPTZ | |

Indexes: `session_id`, `inserted_at`.

**`accounts.query_clusters`** (new): Semantic clusters of similar user queries for admin consolidation.

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | |
| `representative_query` | TEXT | Canonical query for the cluster |
| `entity_player_ids` | UUID[] | Extracted player IDs |
| `entity_team_ids` | UUID[] | Extracted team IDs |
| `topics` | TEXT[] | Normalized keyword topics |
| `query_count` | INTEGER | Member count |
| `scheduled` | BOOLEAN | Whether daily/hourly Exa search is enabled |
| `schedule_frequency` | VARCHAR(20) | `hourly`, `daily`, `disabled` |
| `last_run_at` | TIMESTAMPTZ | |
| `inserted_at` / `updated_at` | TIMESTAMPTZ | |

Indexes: `(scheduled) WHERE scheduled = true`, GIN on `entity_player_ids`.

**`accounts.query_cluster_members`** (new): Maps each user chat message to its cluster.

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | |
| `cluster_id` | UUID FK | `accounts.query_clusters`, ON DELETE CASCADE |
| `message_id` | UUID FK | `accounts.chat_messages`, ON DELETE CASCADE; unique |
| `raw_query` | TEXT | |
| `inserted_at` | TIMESTAMPTZ | |

**`mlb.hit_predictions`** (new): One row per `(prediction_date, player_mlb_id)`. Unique index enforces one prediction per player per date.

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID PK | |
| `pipeline_run_id` | UUID | FK to `system.pipeline_runs` |
| `prediction_date` | DATE | |
| `player_mlb_id` | INTEGER | Not null |
| `player_name` | VARCHAR(200) | |
| `player_team` / `player_team_id` | VARCHAR / INTEGER | |
| `vs_team` / `vs_team_id` | VARCHAR / INTEGER | |
| `game_id` / `game_datetime` | INTEGER / TIMESTAMPTZ | |
| `is_home` / `batting_order` | BOOLEAN / INTEGER | |
| `probable_pitcher_name` / `probable_pitcher_mlb_id` | VARCHAR / INTEGER | |
| `venue_id` / `venue_name` | INTEGER / VARCHAR | |
| `hit_prob` | DOUBLE PRECISION | 0.0–1.0 |
| `prediction` | VARCHAR(10) | `"Hit"` or `"No Hit"` |
| `confidence_tier` | VARCHAR(5) | S / A / B / C / D |
| `temperature`, `wind_speed`, `wind_direction`, `precipitation`, `weathercode`, `surface_pressure` | DOUBLE PRECISION / INTEGER | Weather snapshot at game time |
| `bvp_avg`, `bvp_at_bats`, `bvp_home_runs` | DOUBLE PRECISION / INTEGER | Batter-vs-pitcher summary |
| `features` | JSONB | 44-column feature snapshot for offline analytics |
| `model_version` | VARCHAR(40) | |
| `actual_result` / `actual_hits` | VARCHAR / INTEGER | Backfilled by future ResolveBetsWorker |
| `inserted_at` / `updated_at` | TIMESTAMPTZ | |

Indexes: unique `(prediction_date, player_mlb_id)`, `(prediction_date, hit_prob DESC)`, `player_mlb_id`, `pipeline_run_id`.

**`mlb.pitcher_game_logs`** (new): Per-game pitching stats used for recent-form features.

| Column | Type | Notes |
|--------|------|-------|
| `pitcher_mlb_id` | INTEGER | |
| `game_id` | INTEGER | |
| `game_date` | DATE | |
| `innings_pitched`, `hits_allowed`, `hr_allowed`, `bb_allowed`, `strikeouts`, `earned_runs`, `pitches_thrown` | NUMERIC / INTEGER | |

Unique index: `(pitcher_mlb_id, game_id)`. Index: `(pitcher_mlb_id, game_date)`.

**`mlb.player_statcast`** (new): Season-level Statcast aggregates from Baseball Savant CSV.

| Column | Type | Notes |
|--------|------|-------|
| `player_mlb_id` | INTEGER | |
| `season` | INTEGER | |
| `avg_exit_velocity`, `max_exit_velocity` | DOUBLE PRECISION | |
| `barrel_pct`, `hard_hit_pct` | DOUBLE PRECISION | |
| `avg_launch_angle`, `fb_pct` | DOUBLE PRECISION | |
| `pulled_at` | TIMESTAMPTZ | Last refresh timestamp |

Unique index: `(player_mlb_id, season)`.

**`mlb.park_hr_factors`** (altered): Added `hit_factor DOUBLE PRECISION` column (additive; existing `hr_factor` column unchanged).

**`mlb.pitcher_stats`** (altered): Added `pitcher_mlb_id INTEGER` column to support the pipeline (existing `player_id` UUID FK still present; new rows write via `pitcher_mlb_id`).

Migrations:
- `priv/repo/migrations/20260515190000_create_news_agent_tables.exs` — agent settings/results tables
- `priv/repo/migrations/20260516100000_create_chat_tables.exs` — chat + query cluster tables
- `priv/repo/migrations/20260516100001_add_news_items_search_vector.exs` — tsvector + GIN index, Exa URL unique index
- `priv/repo/migrations/20260518000001_create_hit_predictions_table.exs` — `mlb.hit_predictions` with all indexes
- `priv/repo/migrations/20260518000002_add_pitcher_training_tables.exs` — `mlb.pitcher_game_logs`, `mlb.player_statcast`, added columns on `mlb.pitcher_stats` and `mlb.park_hr_factors` (all idempotent `ADD COLUMN IF NOT EXISTS`)

---

## Slug Conventions

- **Team slugs**: `new-york-yankees`, `los-angeles-dodgers`, `st-louis-cardinals`
- **Player slugs**: `aaron-judge`, `shohei-ohtani` (full name, lowercase, hyphenated)
- **Collision handling**: Append numeric suffix for duplicate names on same team: `john-smith-2`
- `Slug.slugify/1` is defined in `lib/sports_fanatic/mlb/team.ex` as a top-level module `Slug`. It is accessible project-wide as `Slug.slugify/1`. Future refactor: rename to `SportsFanatic.Slug`.

---

## Valkey Caching

```
sf:page:player:{team}:{slug}              TTL 5 min
sf:page:team:{slug}                       TTL 10 min
sf:page:lineup:today                      TTL 2 min
sf:page:lineup:{past-date}               TTL 24 hours
sf:page:news:{date}:{slug}               TTL 5 min
sf:page:scouting:{team}:{slug}           TTL 15 min
sf:page:gameday:{date}:{slug}            TTL 10 min
sf:data:predictions:*                     TTL 5 min
sf:data:hit_prediction:{mlb_id}:{date}   TTL 5 min  (per-player hit prediction; read by get_for_player/2;
                                                      invalidated by PredictHitsWorker on daily run)
sf:page:predictions:*                     TTL 5 min  (PredictionsLive page cache)
sf:data:news:feed:{date}                  TTL 60 s   (enriched JSON news feed; invalidated by FetchNewsWorker on new articles)
sf:sitemap:*                              TTL 6 hours
```

Use `SportsFanatic.Cache.get/1`, `put/3`, `delete/1`, `invalidate_pattern/1`.

Key builders: `Cache.news_feed_key/1` accepts a `%Date{}` or ISO-8601 string.

Agent settings and results are not cached in Valkey — they are read directly from PostgreSQL per user on each LiveView mount and on `agent:settings:{user_id}` PubSub messages.

---

## Python Bridge

`SportsFanatic.PythonBridge` is the Elixir-side HTTP client. It calls `http://python-bridge:8000` (Docker internal) via `Req`. The circuit breaker (`SportsFanatic.PythonBridge.CircuitBreaker`) trips after 3 consecutive failures and stays open for 5 minutes. `SportsFanatic.PythonBridge.HealthCheck` pings `/health` every 30 seconds.

Available endpoints (called via `PythonBridge.*` functions):
- `POST /inference/hit` — GBT fit+predict (batch). Called by `PythonBridge.score_hits/2` from `Predictions.Inference`. Request: `{training_rows, inference_rows}`; response: `{model_version, training_metrics, predictions: [{player_mlb_id, hit_prob, prediction}]}`. Added in the predictions pipeline migration.
- `POST /scouting/search`, `POST /scouting/generate` — AI scouting reports
- `POST /gameday/generate` — AI Game Day Magazine generation
- `POST /news/analyze` — Claude tool_use classification; returns `{category, sentiment, summary, domain_tags}` for a news headline + excerpt. Called by `FetchNewsWorker` via `PythonBridge.analyze_news/2`. If the circuit breaker is open, articles are stored with `ai_processed: false` for later backfill.
- `POST /agents/parse-setting` — Claude Haiku tool_use parser; accepts `{raw_prompt, context}` and returns structured criteria including `target_players`, `target_teams`, `target_leagues`, `stat_filters`, `categories`, `domain_tags`, `requires_exa_search`, `exa_query`, `confidence`, `interpretation`. Called by `ParseSettingWorker` via `PythonBridge.parse_setting/2`. Rejects prompts over 500 characters. Includes prompt injection guardrails in the system prompt.

**Deleted endpoints** (removed in the predictions pipeline migration): `POST /predict/hit`, `POST /predict/hr`, all `/schedule/*`, `/simulation/*`, `POST /agents/execute`.

**Kept for legacy scouting pipeline** (callers in `lib/sports_fanatic/scouting/pipeline.ex`): `PythonBridge.search_player_multi/1`, `PythonBridge.classify_content/2`. Remove when scouting pipeline is migrated (PRED-002).

The `python-bridge` service uses `expose:` (internal-only) in `docker-compose.yml` — port 8000 is not bound to the host (SEC-007 addressed in this branch).

---

## Oban Workers

All workers live in `lib/sports_fanatic/workers/`. They use `use Oban.Worker, queue: :default, max_attempts: 3` unless otherwise noted.

Cron schedules are defined in `config/config.exs` under `Oban.crontab`. Times are UTC (convert from ET accordingly).

Queues: `default: 10`, `predictions: 4` (heavy ML/DB workers, capped). Additional queues may be defined in `config/config.exs`.

Scheduled cron entries:
- `FetchNewsWorker` — every 1 minute (`* * * * *`). Uses `unique: [period: 55]` to prevent overlap. Most runs are no-ops when no new articles are found.
- `GeneratePlayerSeoWorker` — 4:00 AM UTC daily
- `DailyHitPredictionsWorker` — cron from `PREDICTIONS_CRON_OVERRIDE` env var (default `0 12 * * *` = 8:00 AM EDT). Queue `:predictions`. Gated by `hit_predictions_enabled` feature flag. Args: `%{"date" => iso8601, "force" => boolean}`. Unique `period: 3600`; use `force: true` to bypass within the same hour. Orchestrates all prediction pipeline steps sequentially; each step uses `Task.async_stream` internally.
- `GeneratePredictionsWorker` — 9:30 AM UTC daily (now delegates to `DailyHitPredictionsWorker`)
- `WarmCacheWorker` — every 15 minutes
- `RunNewsAgentsWorker` — `0 13 * * *` (9:00 AM ET during EDT = 13:00 UTC). Gated by `news_agents_enabled` feature flag. Processes each user with active settings sequentially; failures for one user do not block others. Schedule override is configurable via the Joshua admin Agents tab.
- `ConsolidateQueriesWorker` — hourly. Groups new chat messages into `accounts.query_clusters` by entity overlap + keyword similarity (jaro_distance + lowercased keyword intersection). Runs after every batch of new chat messages. Re-clusters incrementally rather than from scratch.
- `ScheduledExaSearchWorker` — per-cluster; enqueued by `ConsolidateQueriesWorker` or admin "Run Now". Calls `ExternalApis.Exa` using the cluster's `representative_query`, runs new articles through the full classify/store pipeline, and updates `last_run_at`. Frequency (hourly/daily/disabled) is stored on the cluster.

Non-scheduled workers (enqueued on demand or by the orchestrator):
- `ParseSettingWorker` — enqueued by `Agents.create_setting/2` immediately after INSERT. Calls `/agents/parse-setting` on the Python Bridge and updates the setting's `parsed_criteria` and `status`. Broadcasts `{:setting_updated, setting}` on `"agent:settings:{user_id}"` PubSub on completion. Error messages stored are generic (internal error details are logged via `Logger.error`).
- `FetchPitcherStatsWorker` — called by orchestrator; queue `:predictions`. Reads probable pitchers from `mlb.scheduled_games`, skips rows refreshed within 24h, upserts into `mlb.pitcher_stats`.
- `FetchBvPWorker` — called by orchestrator; queue `:predictions`. Fetches batter-vs-pitcher stats for all lineup × probable-pitcher pairs; upserts into `mlb.batter_vs_pitcher`.
- `SeedPitcherHistoryWorker` — called by orchestrator; queue `:predictions`. Backfills `mlb.pitcher_game_logs` for last 30 days from `mlb.games` missing starter IDs.
- `SeedStatcastWorker` — called by orchestrator; queue `:predictions`. Fetches Baseball Savant CSV for all lineup hitters not refreshed within 7 days; upserts into `mlb.player_statcast`.
- `ForecastWeatherWorker` — called by orchestrator; queue `:predictions`. Fetches game-time weather from Open-Meteo for each unique venue in today's scheduled games; upserts into `mlb.game_weather_forecast`.
- `PredictHitsWorker` — called by orchestrator; queue `:predictions`. Loads features, calls `Predictions.Inference.score/2` (→ `/inference/hit`), upserts `mlb.hit_predictions`, invalidates Valkey cache, broadcasts `{:hits_ready, date}` on `"predictions:hits:{date}"` PubSub.

To manually enqueue a worker in IEx:
```elixir
%{} |> SportsFanatic.Workers.FetchLineupsWorker.new() |> Oban.insert()
%{} |> SportsFanatic.Workers.RunNewsAgentsWorker.new() |> Oban.insert()
%{"setting_id" => "uuid"} |> SportsFanatic.Workers.ParseSettingWorker.new() |> Oban.insert()
%{} |> SportsFanatic.Workers.ConsolidateQueriesWorker.new() |> Oban.insert()
%{"cluster_id" => "uuid"} |> SportsFanatic.Workers.ScheduledExaSearchWorker.new() |> Oban.insert()
# Run the hit predictions pipeline for today (force: true bypasses uniqueness guard)
%{"date" => Date.to_iso8601(Date.utc_today()), "force" => true}
|> SportsFanatic.Workers.DailyHitPredictionsWorker.new()
|> Oban.insert()
```

---

## Testing Strategy

- **Pure unit tests** (`mix test.unit`): Schema changesets, `Slug.slugify/1`, `has_active_subscription?/1`, cache key builders, circuit breaker state machine, `date_nav/1` component, chat schemas, Exa client, Action behaviour, consolidate/scheduled worker structure, `HitPrediction.tier_for_prob/1`, `OpenMeteo.extract_at_game_time/2`, `Features.feature_cols/0` (count + order), `ParkFactors.hit_factor_static/1` (unknown venue returns 1.0), `Stadiums.coordinates/1` (545 tests total). No PostgreSQL required. Note: Oban is set to `testing: :disabled` in `config/test.exs` because Oban 2.22's `verify_migrated!` requires a live DB even for unit tests.
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
| SEC-007 | MEDIUM | Python bridge port 8000 exposed to host in `docker-compose.yml`. **Addressed in predictions pipeline branch** — `docker-compose.yml` now uses `expose:` instead of `ports:`. |
| CODE-001 | LOW | `Slug` module is not namespaced (`defmodule Slug` in `team.ex`). Works correctly but should be `SportsFanatic.Slug`. |
| CODE-002 | LOW | `Billing.handle_checkout_completed/1` checks wrong path for trial detection. Trial status should come from `customer.subscription.updated` webhook with `status: "trialing"`. |
| AGENTS-001 | LOW | `RunNewsAgentsWorker` matches players/teams via ILIKE text search on `parsed_criteria` JSON values. Phase 2 should resolve to `player_ids`/`team_ids` via `EntityMatcher` for accurate matching. |
| AGENTS-002 | LOW | `POST /agents/execute` on the Python Bridge is a stub returning empty results. Phase 2 activates Exa.ai search and batched multi-user execution. |
| AGENTS-003 | LOW | Domain tags are not backfilled for news articles classified before the `domain_tags` column was added. A one-shot backfill worker should be run post-deployment to re-classify those articles. |
| CHAT-001 | HIGH | Agent output and Exa article content must be sanitized via `html_sanitize_ex` before rendering. The `html_sanitize_ex` dep is added; ensure `raw/1` is never called on chat message content (CHAT-SEC-001). |
| CHAT-002 | MEDIUM | `phx-hook="ScrollBottom"` on the chat container references a JS hook added in `assets/js/app.js`. If the hook fails to register, new messages will not auto-scroll. |
| CHAT-003 | MEDIUM | The `phx-change="update_chat_input"` event on the chat input needs a corresponding `handle_event` clause in `NewsLive` or a `phx-debounce` attribute to avoid excessive server events. |
| CHAT-004 | LOW | Query cluster membership uses entity overlap + keyword intersection (MVP). Semantically similar queries with different surface forms may not cluster (e.g., "Harper" vs "Bryce Harper"). Upgrade to embedding-based similarity post-MVP. |
| CHAT-005 | LOW | Jido v2.x deps (`jido`, `jido_ai`) are not installed due to Elixir 1.18 requirement. The `Action` behaviour in `agents/action.ex` is a plain-Elixir equivalent. If Elixir is upgraded to 1.18+, replace with `use Jido.Action` in each action module. |
| PRED-001 | LOW | Admin Predictions tab cron-override and concurrency-override input fields are deferred — env vars (`PREDICTIONS_CRON_OVERRIDE`, etc.) are the source of truth. The flag toggle and Run Now button are wired. UI inputs tracked for a follow-up iteration. |
| PRED-002 | LOW | `python_bridge.ex` still exports `search_player_multi/1` and `classify_content/2` because `lib/sports_fanatic/scouting/pipeline.ex` actively calls them. Remove when the scouting pipeline is migrated off the Python bridge. |
| PRED-003 | LOW | `system.pipeline_steps` table does not exist. Step metadata is appended into `system.pipeline_runs.metadata` JSONB instead. Create the table in a follow-up if richer per-step telemetry is needed. |
| MED-PRED-001 | MEDIUM | `filter_min_prob` in `PredictionsLive` accepts unbounded float with no clamp to `[0.0, 1.0]` and no NaN/Infinity rejection. Not exploitable today (in-memory filter only) but a defense-in-depth gap. Clamp and reject non-finite before assigning. |
| LOW-PRED-004 | LOW | No global timeout on `DailyHitPredictionsWorker.do_run/1`. Each step has its own `Task.async_stream` timeout, but the orchestrator has no cumulative ceiling. Oban `max_attempts: 3` provides eventual termination; add a 15-minute soft timeout for tighter observability. |
| LOW-PRED-005 | LOW | `Predictions.run_now/1` ("Run Now" in admin) is not rate-limited per admin session beyond Oban's uniqueness window. An admin clicking repeatedly creates redundant jobs. Add a per-session token bucket or tighter Oban `unique: [period: 60]` for the manual-trigger path. |
| LOW-PRED-008 | LOW | Python `/inference/hit` has no per-request row-count cap. FastAPI's 25MB body limit provides some protection; add explicit `len(training_rows) <= 200_000` and `len(inference_rows) <= 5_000` guards to prevent DoS from inside the Docker network. |

Full security audit is in `.on-loop/sessions/20260517_111655_elixir-hit-predictions-pipeline/agent-notes/security.md`.

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

**Add a new chatbot action:**
1. Create a module under `lib/sports_fanatic/agents/actions/` that uses `SportsFanatic.Agents.Action` behaviour.
2. Implement `name/0`, `description/0`, and `run/2` callbacks. `run/2` receives `params` and a `context` map.
3. Register the action in `SportsFanatic.Agents.NewsAgent` (add to the `@actions` module attribute or tool loop).
4. Add corresponding Python Bridge or external API endpoint if needed.

**Note on Jido**: If Elixir is upgraded to 1.18+, replace `use SportsFanatic.Agents.Action` with `use Jido.Action` in each action module and add `{:jido, "~> 2.2"}, {:jido_ai, "~> 2.1"}` to `mix.exs`.

**Enable/disable the chatbot:**
- Toggle `news_chatbot_enabled` via the Joshua admin Queries tab at `/admin`.
- When disabled, `NewsLive` renders the legacy textarea command input instead of the chat UI.

**Manually trigger query consolidation:**
```elixir
# IEx
%{} |> SportsFanatic.Workers.ConsolidateQueriesWorker.new() |> Oban.insert()
```

**Manually run a scheduled Exa search for a cluster:**
```elixir
# IEx
%{"cluster_id" => "uuid-here"} |> SportsFanatic.Workers.ScheduledExaSearchWorker.new() |> Oban.insert()
```

**Backfill domain_tags for existing articles:**
```elixir
# Enqueue a one-shot backfill — implement as a temporary Oban worker that queries
# news_items WHERE domain_tags = '{}' and re-calls PythonBridge.analyze_news/2
```

**Enable/disable hit predictions:**
- Toggle `hit_predictions_enabled` via the Joshua admin Predictions tab at `/admin`.
- When disabled, `DailyHitPredictionsWorker` returns `:ok` immediately without writing any rows.

**Manually run hit predictions for today:**
```elixir
# IEx
%{"date" => Date.to_iso8601(Date.utc_today()), "force" => true}
|> SportsFanatic.Workers.DailyHitPredictionsWorker.new()
|> Oban.insert()
```

**Manually run hit predictions for a specific date:**
```elixir
# IEx
%{"date" => "2026-05-10", "force" => true}
|> SportsFanatic.Workers.DailyHitPredictionsWorker.new()
|> Oban.insert()
```

**Read today's predictions from context:**
```elixir
# IEx
SportsFanatic.Predictions.list_today([])
SportsFanatic.Predictions.get_for_player(592450, Date.utc_today())
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

**Chatbot and AI environment variables:**

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `ANTHROPIC_API_KEY` | Claude API key used by the Python Bridge (news classify, scouting, game day) and by the Elixir-side agent reasoning | — | Yes |
| `EXA_API_KEY` | Exa.ai API key for the Elixir-side `ExternalApis.Exa` client (chatbot article discovery) | — | Yes when chatbot enabled |

**Hit Predictions environment variables:**

| Variable | Description | Default | Required |
|----------|-------------|---------|----------|
| `OPENMETEO_API_KEY` | Open-Meteo API key (free tier requires no key; set only for paid plan) | _(blank)_ | No |
| `PREDICTIONS_CONCURRENCY` | Default `max_concurrency` for steps without a step-specific override | `8` | No |
| `PREDICTIONS_CRON_OVERRIDE` | Oban cron expression for `DailyHitPredictionsWorker` | `0 12 * * *` | No |
| `PREDICTIONS_PITCHER_STATS_CONCURRENCY` | `FetchPitcherStatsWorker` step concurrency | `4` | No |
| `PREDICTIONS_BVP_CONCURRENCY` | `FetchBvPWorker` step concurrency | `6` | No |
| `PREDICTIONS_STATCAST_CONCURRENCY` | `SeedStatcastWorker` step concurrency | `4` | No |
| `PREDICTIONS_SEED_PITCHER_CONCURRENCY` | `SeedPitcherHistoryWorker` step concurrency | `4` | No |
| `PREDICTIONS_WEATHER_CONCURRENCY` | `ForecastWeatherWorker` step concurrency | `8` | No |
| `PREDICTIONS_FEATURE_COMPUTE_CONCURRENCY` | Per-player feature computation concurrency in `PredictHitsWorker` | `16` | No |

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
