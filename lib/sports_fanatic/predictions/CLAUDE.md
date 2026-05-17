Parent: `../../../CLAUDE.md`

# CLAUDE.md — Hit Predictions

> See the Documentation Placement Rule in `../../../CLAUDE.md` before adding
> content here.

---

A daily Elixir-native pipeline that seeds hitter and pitcher data, computes a 44-column feature vector per player, scores them via a GradientBoosting model in the Python bridge, and persists per-player hit probabilities to `mlb.hit_predictions`. Results are surfaced on the public `/predictions` LiveView and as a "Today's Hit Prediction" banner on player detail and scouting report pages.

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
| `SportsFanatic.Predictions` | `../predictions.ex` | Context API: `list_for_date/2`, `get_for_player/2`, `list_today/1`, `list_runs/1`, `run_now/1`, `stream_player_results/1` |
| `SportsFanatic.Predictions.HitPrediction` | `hit_prediction.ex` | Ecto schema for `mlb.hit_predictions`; `tier_for_prob/1` (S/A/B/C/D) |
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

## Workers

All use `queue: :predictions, max_attempts: 3`. The orchestrator (`DailyHitPredictionsWorker`) calls each step's `perform/1` directly (sequentially) so step ordering is deterministic. Step-level parallelism happens via `Task.async_stream` inside each worker.

See `../workers/CLAUDE.md` for the full worker catalogue. Predictions-specific entries:

| Worker | File | Purpose |
|--------|------|---------|
| `DailyHitPredictionsWorker` | `../workers/daily_hit_predictions_worker.ex` | Cron orchestrator; opens `system.pipeline_runs` row; sequences all steps |
| `FetchPitcherStatsWorker` | `../workers/fetch_pitcher_stats_worker.ex` | Upserts probable-pitcher season stats into `mlb.pitcher_stats` |
| `FetchBvPWorker` | `../workers/fetch_bvp_worker.ex` | Upserts batter-vs-pitcher records into `mlb.batter_vs_pitcher` |
| `SeedPitcherHistoryWorker` | `../workers/seed_pitcher_history_worker.ex` | Backfills `mlb.pitcher_game_logs` for the last 30 days |
| `SeedStatcastWorker` | `../workers/seed_statcast_worker.ex` | Upserts Statcast aggregates into `mlb.player_statcast` via Baseball Savant CSV |
| `ForecastWeatherWorker` | `../workers/forecast_weather_worker.ex` | Upserts game-time weather into `mlb.game_weather_forecast` via Open-Meteo |
| `PredictHitsWorker` | `../workers/predict_hits_worker.ex` | Builds features, calls `/inference/hit`, upserts `mlb.hit_predictions`, invalidates cache, broadcasts PubSub |

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
| `OPENMETEO_API_KEY` | _(blank)_ | Optional — Open-Meteo free tier requires no key |

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
