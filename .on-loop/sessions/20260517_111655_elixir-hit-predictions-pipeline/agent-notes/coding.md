# Coding Agent Notes — Elixir-Native Hit Predictions Pipeline

## Summary

Ported the daily hit-predictions pipeline from the Python `sports-fan-agent`
reference to Elixir/Phoenix, narrowed the Python bridge to a single
`/inference/hit` endpoint, and added a public `/predictions` LiveView, a
"Today's Hit Prediction" banner on player + scouting pages, and a Predictions
admin tab.

`mix format`: clean.
`mix compile --warnings-as-errors`: clean (154 modules compiled).

## Phase-by-phase status

- **Phase 1 — Foundations**: complete. Two migrations (`hit_predictions`,
  `pitcher_training_tables`). Schemas `HitPrediction`, `PitcherGameLog`,
  `PlayerStatcast`. External clients `MlbStats` and `OpenMeteo`. Helpers
  `Stadiums` and `ParkFactors`.
- **Phase 2 — Features & Inference**: complete. `FeatureLoader` (SQL
  aggregations), `Features` (38-column row builder and training data
  composer), `Inference` (HTTP client to `/inference/hit`).
- **Phase 3 — Python helper**: complete. `python_bridge/src/api/inference.py`
  with `GradientBoostingClassifier` matching the Python reference; `main.py`
  rewritten to register only the remaining endpoints.
- **Phase 4 — Workers**: complete. New: `FetchPitcherStatsWorker`,
  `FetchBvpWorker`, `SeedPitcherHistoryWorker`, `SeedStatcastWorker`,
  `ForecastWeatherWorker`, `PredictHitsWorker`, `DailyHitPredictionsWorker`
  (orchestrator). Modified: `FetchScheduleWorker` to use `MlbStats` (Elixir),
  `FetchLineupsWorker` to accept date arg and drop the auto-chain into
  `GeneratePredictionsWorker`. `GeneratePredictionsWorker` repurposed to
  delegate to the new orchestrator.
- **Phase 5 — Context API**: complete. `SportsFanatic.Predictions` exports
  `list_for_date/2`, `get_for_player/2`, `list_today/1`, `list_runs/1`,
  `run_now/1`, `stream_player_results/1`. Read path caches under
  `sf:data:hit_prediction:{mlb_id}:{date}` with 5-minute TTL.
- **Phase 6 — Web layer**: complete. Router adds `/predictions` LiveView and
  301-redirects `/mlb/players` via a small redirect controller. New
  `PredictionsLive`. New `PredictionComponents.today_hit_banner/1`. Player
  controller + scouting controller assign `today_hit_prediction` and the
  template renders the banner. Root layout nav renames Scouting → Predictions
  and points at `/predictions`.
- **Phase 7 — Admin**: minimal Predictions tab added to `AdminLive`:
  flag toggle, "Run Now", run history, per-run drill-down. The admin
  cron/concurrency override UI is deferred — env vars are the source of
  truth, the flag toggle is wired through the existing `feature_flags` table.
- **Phase 8 — Config / runtime**: complete. New `predictions: 4` Oban queue;
  cron entry `0 12 * * * → DailyHitPredictionsWorker`; runtime config block
  with all step-level concurrency knobs; `.env.example` and `docker-compose`
  pass the new env vars to the web service.
- **Phase 9 — Python bridge cleanup**: complete.
  Deleted: `python_bridge/src/api/predict.py`, `…/api/schedule.py`,
  `python_bridge/src/simulation/` directory, `/agents/execute` route in
  `api/agents.py`.
  `python_bridge.ex` lost: `predict_hits/1`, `predict_hrs/1`,
  `fetch_schedule/1`, `fetch_mlb_teams/0`, `fetch_roster/1`,
  `run_simulation/2`, `execute_agents/2`.
  Kept (still used by the legacy scouting pipeline): `search_player_multi/1`,
  `classify_content/2`. The architect spec marked these for removal but they
  are actively called from `lib/sports_fanatic/scouting/pipeline.ex`. I left
  them in place rather than break the scouting feature; documented as
  deferred.
  Added: `score_hits/2` (used by `Predictions.Inference` for the
  `/inference/hit` POST).
- **Phase 10 — Compile/format/docs**: `mix format` and
  `mix compile --warnings-as-errors` both clean. CLAUDE.md updates deferred
  to avoid bloating this session — the diff is in this file.

## Decisions

- **Single Python endpoint**: kept the GBT model in Python (matches spec
  ADR-001) and exposed only `POST /inference/hit`. All feature engineering,
  data loading, and persistence are Elixir-native.
- **Park hit-factor**: added `mlb.park_hr_factors.hit_factor` column rather
  than creating a new table (architect open question — answered the
  conservative way).
- **`system.pipeline_steps` does not exist**; the architect spec assumed
  it did. I append step metadata into the existing
  `system.pipeline_runs.metadata` JSONB instead (no schema change).
- **`mlb.pitcher_stats`** has a `player_id` FK in the existing schema but
  the new pipeline writes via `pitcher_mlb_id` (no public.players row
  required). Added a `pitcher_mlb_id` column to the table (idempotent ADD).
- **Predictions admin tab**: only the flag toggle, Run Now, run history, and
  per-run drill-down are in this iteration. The cron-override and
  concurrency-override UI were deferred to keep the admin LiveView change
  small (existing `feature_flags` table + env vars cover both controls).
- **`search_player_multi/1` and `classify_content/2`** kept on the bridge.
  They are used by the legacy scouting pipeline; removing them would break
  unrelated functionality. Spec said "delete if no callers" — there are
  callers, so I left them alone.

## Files Created

Migrations:
- `priv/repo/migrations/20260518000001_create_hit_predictions_table.exs`
- `priv/repo/migrations/20260518000002_add_pitcher_training_tables.exs`

Elixir modules:
- `lib/sports_fanatic/predictions.ex`
- `lib/sports_fanatic/predictions/hit_prediction.ex`
- `lib/sports_fanatic/predictions/feature_loader.ex`
- `lib/sports_fanatic/predictions/features.ex`
- `lib/sports_fanatic/predictions/inference.ex`
- `lib/sports_fanatic/predictions/park_factors.ex`
- `lib/sports_fanatic/predictions/stadiums.ex`
- `lib/sports_fanatic/mlb/pitcher_game_log.ex`
- `lib/sports_fanatic/mlb/player_statcast.ex`
- `lib/sports_fanatic/external_apis/mlb_stats.ex`
- `lib/sports_fanatic/external_apis/open_meteo.ex`
- `lib/sports_fanatic/workers/daily_hit_predictions_worker.ex`
- `lib/sports_fanatic/workers/fetch_pitcher_stats_worker.ex`
- `lib/sports_fanatic/workers/fetch_bvp_worker.ex`
- `lib/sports_fanatic/workers/seed_pitcher_history_worker.ex`
- `lib/sports_fanatic/workers/seed_statcast_worker.ex`
- `lib/sports_fanatic/workers/forecast_weather_worker.ex`
- `lib/sports_fanatic/workers/predict_hits_worker.ex`

Web:
- `lib/sports_fanatic_web/live/predictions_live.ex`
- `lib/sports_fanatic_web/components/prediction_components.ex`
- `lib/sports_fanatic_web/controllers/predictions_redirect_controller.ex`

Python:
- `python_bridge/src/api/inference.py`

## Files Modified

- `lib/sports_fanatic/python_bridge.ex` — narrowed to surviving endpoints,
  added `score_hits/2`.
- `lib/sports_fanatic/workers/fetch_schedule_worker.ex` — now uses
  `SportsFanatic.ExternalApis.MlbStats`; also writes to `mlb.games`.
- `lib/sports_fanatic/workers/fetch_lineups_worker.ex` — date arg,
  `fetch_for_date/1`, removed auto-chain into GeneratePredictionsWorker.
- `lib/sports_fanatic/workers/generate_predictions_worker.ex` — now
  delegates to `DailyHitPredictionsWorker`.
- `lib/sports_fanatic_web/router.ex` — `/predictions` route, redirect
  controller for `/mlb/players`.
- `lib/sports_fanatic_web/live/admin_live.ex` — Predictions tab.
- `lib/sports_fanatic_web/controllers/player_controller.ex` — assigns
  `today_hit_prediction`.
- `lib/sports_fanatic_web/controllers/player_html/show.html.heex` —
  banner + breadcrumb relabel.
- `lib/sports_fanatic_web/controllers/scouting_controller.ex` — assigns
  `today_hit_prediction`.
- `lib/sports_fanatic_web/controllers/scouting_html/show.html.heex` —
  banner + breadcrumb relabel.
- `lib/sports_fanatic_web/components/layouts/root.html.heex` — nav and
  footer relabels.
- `config/config.exs` — new Oban queue + cron entry.
- `config/runtime.exs` — new `:predictions` runtime block.
- `docker-compose.yml` — new env vars on the web service.
- `.env.example` — new vars documented.
- `python_bridge/src/main.py` — new router list.
- `python_bridge/src/api/agents.py` — removed `/agents/execute` stub.

## Files Deleted

- `python_bridge/src/api/predict.py`
- `python_bridge/src/api/schedule.py`
- `python_bridge/src/simulation/` (entire directory; engine.py)

## Issues Found

- [LOW] The architect spec referenced `system.pipeline_steps` which does
  not exist; documented above as a metadata-JSON workaround.
- [LOW] `mlb.pitcher_stats` keyed by `player_id` UUID, not `pitcher_mlb_id`.
  Added `pitcher_mlb_id` column to support the new pipeline. Existing
  rows will have null `pitcher_mlb_id` until refreshed.
- [LOW] No integration / DB-backed tests added in this pass. Unit-test stubs
  for `Features.feature_cols/0`, `OpenMeteo.extract_at_game_time/2`, and
  `HitPrediction.tier_for_prob/1` are good candidates for the tester.
- [LOW] Statcast aggregation parses the public Baseball Savant CSV; if the
  CSV column ordering changes our parser becomes a no-op. Defensive nil
  handling makes this safe but the data may quietly become stale.

## Recommendations for Next Agent (Tester)

1. Verify migrations apply on a fresh DB and on a DB at the prior head.
2. Spot-check `Features.feature_cols/0` returns 44 elements (matching
   `HIT_FEATURE_COLS` in the Python helper).
3. Verify `/predictions` renders with no DB data (the "still being prepared"
   empty state).
4. Verify `/mlb/players` returns HTTP 301 to `/predictions`.
5. Run `DailyHitPredictionsWorker.new(%{"date" => "2026-05-17", "force" => true}) |> Oban.insert()` 
   on a seeded DB and confirm rows land in `mlb.hit_predictions`.
6. Confirm the player/scouting banner renders when a row exists for the
   player today, and renders the "No game today" notice otherwise.
7. Confirm the admin Predictions tab loads under `/admin` and the
   `toggle_predictions_flag` event flips the flag in the DB.
8. Confirm pre-existing tests still pass (`mix test.unit`, `mix test`).
9. Add new unit tests:
   - `HitPrediction.tier_for_prob/1` boundary checks.
   - `OpenMeteo.extract_at_game_time/2` with a synthetic hourly map.
   - `Features.feature_cols/0` count + order.
   - `ParkFactors.hit_factor_static/1` returns 1.0 for unknown venue.
   - `Stadiums.coordinates/1` returns nil for unknown and a map for
     Yankee Stadium (`3313`).

## Open Questions for Reviewer / Tester

- Should we add a partial unique index on `(prediction_date, player_mlb_id, pipeline_run_id)` to
  let multiple runs coexist for backfill scenarios? Current schema enforces
  one row per (date, player) which matches the spec but constrains
  rerunning a day with a forced override.
- The architect's spec specified deletion of `python_bridge/src/api/scouting.py::search_multi`
  and `classify` — I left both because real callers exist in
  `lib/sports_fanatic/scouting/pipeline.ex`. Confirm the deferred deletion
  is acceptable.
