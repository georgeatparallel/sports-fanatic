Parent: `../../../CLAUDE.md`

# CLAUDE.md — Hit Predictions

> See the Documentation Placement Rule in `../../../CLAUDE.md` before adding
> content here.

---

A daily Elixir-native pipeline that seeds hitter and pitcher data, computes a 44-column feature vector per player, scores them via a GradientBoosting model in the Python bridge, and persists per-player hit probabilities to `mlb.hit_predictions`. Results are surfaced on the public `/predictions` LiveView and as a "Today's Hit Prediction" banner on player detail and scouting report pages.

Streaming progress events (per-step, per-item) flow through
`SportsFanatic.Predictions.Progress` into `system.pipeline_run_events` and
Phoenix PubSub (topics `predictions:pipeline:<run_id>` and
`predictions:pipeline:all`) so the admin UI streams the run live. Failures
halt downstream steps and persist a checkpoint for Oban retries to resume from.

## Data flow (daily, 8:00 AM ET)

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

## Feature flag

`hit_predictions_enabled` — toggled via the Joshua admin Predictions tab at `/admin`. When disabled, `DailyHitPredictionsWorker` returns `:ok` immediately without writing any rows.

## Cron

Default `0 12 * * *` (8:00 AM EDT = 12:00 UTC). Winter override to `0 13 * * *` via `PREDICTIONS_CRON_OVERRIDE`. Loaded from env at startup in `config/runtime.exs`; no rebuild required.

## Modules

| Module | File | Purpose |
|--------|------|---------|
| `SportsFanatic.Predictions` | `../predictions.ex` | Context API: `list_for_date/2`, `get_for_player/2`, `list_today/1`, `list_runs/1`, `list_run_events/2`, `current_running_run/0`, `earliest_data_date/0`, `start_initial_seed/0`, `run_now/1`, `stream_player_results/1` |
| `SportsFanatic.Predictions.HitPrediction` | `hit_prediction.ex` | Ecto schema for `mlb.hit_predictions`; `tier_for_prob/1` (S/A/B/C/D) |
| `SportsFanatic.Predictions.PipelineRunEvent` | `pipeline_run_event.ex` | Ecto schema for `system.pipeline_run_events` (streaming progress audit trail) |
| `SportsFanatic.Predictions.Progress` | `progress.ex` | Fire-and-forget streaming progress sink — `start_run/2`, `step_started/3`, `item_progress/4`, `step_completed/3`, `step_failed/4`, `run_completed/2`, `run_failed/3`, `mark_current_step/2`, `checkpoint/2` |
| `SportsFanatic.Predictions.FeatureLoader` | `feature_loader.ex` | SQL aggregations for training and inference data |
| `SportsFanatic.Predictions.Features` | `features.ex` | 44-column feature row builder; `feature_cols/0`, `build_inference_row/3`, `build_training_rows/2` |
| `SportsFanatic.Predictions.Inference` | `inference.ex` | HTTP client to `POST /inference/hit`; uses shared circuit breaker |
| `SportsFanatic.Predictions.ParkFactors` | `park_factors.ex` | Static `DEFAULT_PARK_HIT_FACTORS` table + DB lookup; `hit_factor_static/1` returns 1.0 for unknown venues |
| `SportsFanatic.Predictions.Stadiums` | `stadiums.ex` | Venue-ID → lat/lon map |

Sibling schemas pulled in by the pipeline (live under `../mlb/`):

| Module | File | Schema |
|--------|------|--------|
| `SportsFanatic.Mlb.PitcherGameLog` | `../mlb/pitcher_game_log.ex` | `mlb.pitcher_game_logs` |
| `SportsFanatic.Mlb.PlayerStatcast` | `../mlb/player_statcast.ex` | `mlb.player_statcast` |

External clients (under `../external_apis/`):

| Module | File | Purpose |
|--------|------|---------|
| `SportsFanatic.ExternalApis.MlbStats` | `../external_apis/mlb_stats.ex` | MLB Stats API via `Req` — schedule, boxscore, season stats, statcast, BvP, lookup |
| `SportsFanatic.ExternalApis.OpenMeteo` | `../external_apis/open_meteo.ex` | Open-Meteo forecast + archive; `extract_at_game_time/2` |

## Run kinds and resumability

`system.pipeline_runs.run_kind` (`daily` | `manual` | `initial_seed`)
distinguishes the orchestrator from the InitialSeedWorker. Each successful
step writes its name into `pipeline_runs.checkpoint.completed_steps` (for
`daily`/`manual`) or `completed_dates` (for `initial_seed`). On Oban retry,
the orchestrator skips entries in `completed_steps`; InitialSeedWorker
skips dates in `completed_dates`. **Halt-on-any-failure** is the new rule
— a single failing step halts the chain and persists the failure on
`pipeline_runs.error`.

## Progress contract

`Progress.*` functions are fire-and-forget. Any DB or PubSub error is
rescued at `:warning` and the pipeline continues. When the `run_id` is
`nil` (e.g. pre-migration deploy) all functions no-op. Per-run monotonic
sequence numbers come from the ETS table `:predictions_progress_seq`
(started in `lib/sports_fanatic/application.ex`).

Payloads are sanitised before persistence: nil keys stripped, `endpoint`
query-string secrets (`apikey`, `key`, `token`, ...) scrubbed, `error`
strings truncated to 4 KB. **Never log Stripe keys, X tokens, DB URLs, or
session cookies — they must never reach `pipeline_run_events.payload`.**

## Workers

All use `queue: :predictions, max_attempts: 3` (`InitialSeedWorker` uses
`max_attempts: 5` because the backfill is long-running). The orchestrator
(`DailyHitPredictionsWorker`) calls each step's `perform/1` directly
(sequentially) so step ordering is deterministic. Step-level parallelism
happens via `Task.async_stream` inside each worker.

See `../workers/CLAUDE.md` for the full worker catalogue. Predictions-specific entries:

| Worker | File | Purpose |
|--------|------|---------|
| `DailyHitPredictionsWorker` | `../workers/daily_hit_predictions_worker.ex` | Cron orchestrator; opens `system.pipeline_runs` row; sequences all steps; halt-on-any-failure + checkpoint resume |
| `InitialSeedWorker` | `../workers/initial_seed_worker.ex` | On-demand 2021-backfill; date-by-date with per-date checkpointing; runs archive-mode weather |
| `FetchPitcherStatsWorker` | `../workers/fetch_pitcher_stats_worker.ex` | Upserts probable-pitcher season stats into `mlb.pitcher_stats` (`force: true` bypasses 24h freshness check) |
| `FetchBvPWorker` | `../workers/fetch_bvp_worker.ex` | Upserts batter-vs-pitcher records into `mlb.batter_vs_pitcher` |
| `SeedPitcherHistoryWorker` | `../workers/seed_pitcher_history_worker.ex` | Backfills `mlb.pitcher_game_logs` for the last 30 days; `run_for_date/2` for historical mode |
| `SeedStatcastWorker` | `../workers/seed_statcast_worker.ex` | Upserts Statcast aggregates into `mlb.player_statcast` via Baseball Savant CSV; `run_for_date_range/3` for historical mode |
| `ForecastWeatherWorker` | `../workers/forecast_weather_worker.ex` | Upserts game-time weather into `mlb.game_weather_forecast` via Open-Meteo; `mode: :archive` routes to historical endpoint |
| `PredictHitsWorker` | `../workers/predict_hits_worker.ex` | Builds features, calls `/inference/hit`, upserts `mlb.hit_predictions`, invalidates cache, broadcasts PubSub (every 50 feature events) |

## Routes

- `/predictions` — `PredictionsLive` (LiveView, public). Today's predictions sorted by hit % desc. See `../../sports_fanatic_web/live/CLAUDE.md`.
- `GET /mlb/players` — 301 redirect to `/predictions` via `PredictionsRedirectController`. Player detail `/mlb/players/:team/:player` is unchanged.

## Scouting + Player Detail Banner

`PlayerController.show/2` and `ScoutingController.show/2` both assign `@today_hit_prediction` via `Predictions.get_for_player(player_mlb_id, today)`. The `<.today_hit_banner prediction={@today_hit_prediction} />` component (in `../../sports_fanatic_web/components/prediction_components.ex`) renders hit %, matchup (Team vs OppTeam), local game time, probable opposing pitcher, and a weather one-liner. When the player has no game today the banner shows "No game today."

## Admin Predictions tab

`/admin` exposes a "Predictions" tab. Events listed in `../../sports_fanatic_web/live/CLAUDE.md`.

Concurrency / cron overrides are env-driven (no admin form) — see "Tunable concurrency" below.

## Python Bridge changes

- **Added**: `POST /inference/hit` (`python_bridge/src/api/inference.py`) — fits a `GradientBoostingClassifier` on supplied training rows and predicts on inference rows. Response: `{model_version, training_metrics, predictions: [{player_mlb_id, hit_prob, prediction}]}`.
- **Removed**: `/predict/hit`, `/predict/hr`, `/schedule/*`, `/simulation/*`, `/agents/execute`.
- **Retained**: `/scouting/search`, `/scouting/generate`, `/news/analyze`, `/gameday/generate`, `/agents/parse-setting`.

See `../../../python_bridge/CLAUDE.md` for the full endpoint catalogue.

## Tunable concurrency

All values come from `Application.get_env(:sports_fanatic, :predictions)` at runtime (set in `config/runtime.exs`). Env changes apply on restart — no recompile needed.

| Env Var | Default | Controls |
|---------|---------|----------|
| `PREDICTIONS_CONCURRENCY` | `8` | Default for steps without a step-specific override |
| `PREDICTIONS_CRON_OVERRIDE` | `0 12 * * *` | Oban cron expression for `DailyHitPredictionsWorker` |
| `PREDICTIONS_PITCHER_STATS_CONCURRENCY` | `4` | `FetchPitcherStatsWorker` `Task.async_stream` concurrency |
| `PREDICTIONS_BVP_CONCURRENCY` | `6` | `FetchBvPWorker` `Task.async_stream` concurrency |
| `PREDICTIONS_STATCAST_CONCURRENCY` | `4` | `SeedStatcastWorker` `Task.async_stream` concurrency |
| `PREDICTIONS_SEED_PITCHER_CONCURRENCY` | `4` | `SeedPitcherHistoryWorker` `Task.async_stream` concurrency |
| `PREDICTIONS_WEATHER_CONCURRENCY` | `8` | `ForecastWeatherWorker` `Task.async_stream` concurrency |
| `PREDICTIONS_FEATURE_COMPUTE_CONCURRENCY` | `16` | `PredictHitsWorker` per-player feature computation concurrency |
| `OPENMETEO_API_KEY` | _(blank)_ | Optional — Open-Meteo free tier requires no key. Falls back to `OPENMATEO_API_KEY` (deprecated spelling) with a one-shot warning at boot. |
| `PREDICTIONS_OPEN_METEO_TIMEOUT_MS` | `15000` | Per-request timeout for Open-Meteo HTTP calls (forecast + archive). |
| `PREDICTIONS_INITIAL_SEED_FROM` | `2021-03-01` | Lower bound for `InitialSeedWorker`. |
| `PREDICTIONS_INITIAL_SEED_CONCURRENCY` | `1` | Dates processed in parallel by `InitialSeedWorker`. Keep at 1 unless ops-approved. |
| `PREDICTIONS_HISTORICAL_BATCH_DAYS` | `1` | Dates per checkpoint write during initial seed (>1 reduces UPDATE pressure). |

## Data tables

Schemas live in `priv/repo/migrations/`. Quick reference (full catalogue in `../../../priv/repo/migrations/CLAUDE.md`):

- `mlb.hit_predictions` — output table; unique `(prediction_date, player_mlb_id)`; `Repo.insert_all` with `on_conflict: {:replace_all_except, [:id, :inserted_at, :pipeline_run_id, :actual_result, :actual_hits]}`
- `mlb.pitcher_game_logs` — seeded by `SeedPitcherHistoryWorker`
- `mlb.player_statcast` — seeded by `SeedStatcastWorker`
- `mlb.pitcher_stats`, `mlb.batter_vs_pitcher`, `mlb.game_weather_forecast` — upserted by the corresponding workers

## Cache

| Key pattern | TTL | Owner |
|-------------|-----|-------|
| `sf:data:hit_prediction:{player_mlb_id}:{date}` | 5 min | `Predictions.get_for_player/2` |
| `sf:data:predictions:{date}` | 5 min | `Predictions.list_for_date/2` |

Invalidated by `PredictHitsWorker` after each successful run.

## PubSub

- Topic: `"predictions:hits:{date}"` — broadcasts `{:hits_ready, date}` after a successful `PredictHitsWorker` run; `PredictionsLive` re-renders.
- Topic: `"predictions:pipeline:<run_id>"` — per-run streaming progress
  events. Subscribers receive `{:predictions_pipeline_event, %{run_id,
  run_kind, step, kind, inserted_at, payload}}` messages.
- Topic: `"predictions:pipeline:all"` — fan-in topic carrying every
  progress event. The admin Predictions tab subscribes here on mount so it
  can render the Currently-Running panel without knowing the run id.

## Initial Seed Runbook

### Preconditions

- `OPENMETEO_API_KEY` should be set for the paid Open-Meteo plan (100k
  calls/day). Without it the free tier (10k calls/day) means the archive
  steps alone (~22.5k calls across a full 2021–present backfill) will
  throttle across ~3 days. The seed worker handles this gracefully via
  checkpoint + resume, but total wall-clock time will be longer.
- Both migrations must have run: `mix ecto.migrate` (includes
  `20260518200001_create_pipeline_run_events.exs` and
  `20260518200002_add_run_kind_to_pipeline_runs.exs`).

### Step-by-step

1. Log into `/joshua` with the passphrase.
2. Navigate to `/admin` → click the **Predictions** tab.
3. The **Initial Backfill** card shows:
   - "Earliest data in DB: `<date or (none)>`"
   - "Will seed: `2021-03-01` → `<yesterday>`"
4. Click **Start Initial Seed**. A confirmation modal appears:
   "Backfill from 2021-03-01 → yesterday. This takes 4-8 hours and makes
   ~284k API calls. Continue?"
5. Confirm. A flash message confirms the Oban job is enqueued with its job id
   and date range.

### What to watch

- The **Currently-Running panel** in the Predictions tab updates in real time
  (step name, current item, processed/total counter, progress bar).
- To inspect raw progress in Postgres:

  ```sql
  SELECT checkpoint->>'completed_dates' FROM system.pipeline_runs
   WHERE run_kind = 'initial_seed' ORDER BY started_at DESC LIMIT 1;
  ```

  The `completed_dates` JSON array grows by one ISO date string per completed
  date. Divide its length by total dates to gauge progress.
- Event detail is in `system.pipeline_run_events` (retained 7 days):

  ```sql
  SELECT step, kind, payload FROM system.pipeline_run_events
   WHERE pipeline_run_id = '<run-id>'
   ORDER BY seq DESC LIMIT 50;
  ```

### Resuming after a kill

Oban will retry automatically (up to `max_attempts: 5`). On each retry the
worker reads `checkpoint.completed_dates` and skips already-finished dates.
To trigger a manual retry from IEx:

```elixir
%{"seed_from" => "2021-03-01", "seed_through" => "<yesterday-iso>"}
|> SportsFanatic.Workers.InitialSeedWorker.new()
|> Oban.insert()
```

The `unique` constraint (scoped to `seed_from + seed_through`) prevents a
duplicate job from being enqueued if one is already running or retrying.

### Expected duration

| Open-Meteo plan | Estimated wall-clock |
|-----------------|----------------------|
| Paid (100k/day) | 4–8 hours |
| Free (10k/day)  | ~3 days (seed resumes across days via checkpoint) |

Default `PREDICTIONS_INITIAL_SEED_CONCURRENCY=1` (sequential dates). Setting
it to 2–4 can halve the time but increases API call rate — confirm MLB Stats
rate tolerance first.

### Reading the failure banner

When a step fails, the admin Predictions tab shows a red **Failure banner**:

- **Failed at step** — the step name (e.g. `seed_pitcher_history`)
- **item** — the player name + MLB ID or venue + venue_id
- **endpoint** — the static API base URL (apikey query params are scrubbed)
- **HTTP status** — e.g. `503`
- **raw error** — the full `inspect(error)` string (truncated to 4 KB)

Copy/paste the raw error string into a debugger session. Clicking **Re-run**
on the banner enqueues a fresh `DailyHitPredictionsWorker` with `force: true`;
for `InitialSeedWorker` re-runs, use IEx (see "Resuming after a kill" above).

### DoS amplification note

One click of **Start Initial Seed** generates up to ~284k outbound HTTP
calls (MLB Stats, Baseball Savant, Open-Meteo). Do not click it repeatedly.
The Oban `unique` constraint prevents duplicate enqueues of the same date
range, but two Joshua sessions with a one-day offset in their computed
`seed_through` dates could produce two concurrent seed jobs. If you see two
`initial_seed` rows in `system.pipeline_runs`, cancel the duplicate via
the Oban admin or `Oban.cancel_job/1`.
