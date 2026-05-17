# Implementation Plan — Elixir-Native Hit Predictions Pipeline

**Session**: 20260517_111655_elixir-hit-predictions-pipeline
**Branch**: on-loop/elixir-hit-predictions-pipeline
**Worktree**: `/Users/charmalloc/dev/sports-fanatic/.claude/worktrees/elixir-hit-predictions-pipeline/`
**Spec**: `agent-notes/architect.md`

All work happens in the worktree, not the original repo root.

---

## Phase 1 — Foundations (migrations + schemas + clients)

Bottom-up so later layers compile.

1. **Migrations** (`priv/repo/migrations/`):
   - `20260518000001_create_hit_predictions_table.exs` — `mlb.hit_predictions` table per spec §Schemas/Migrations with all three indexes and unique `(prediction_date, player_mlb_id)`.
   - `20260518000002_add_pitcher_training_tables.exs` — idempotent ADDs for `mlb.pitcher_game_logs`, `mlb.player_statcast`, missing `mlb.pitcher_stats` columns, `mlb.park_hr_factors.hit_factor`.
   - Both must use `IF NOT EXISTS` / `ADD COLUMN IF NOT EXISTS` and provide non-trivial `down` for rollback.
2. **Ecto schemas**:
   - New: `SportsFanatic.Predictions.HitPrediction` (`@schema_prefix "mlb"`, source `"hit_predictions"`, binary_id PK, `changeset/2` for upsert).
   - New (if absent): `SportsFanatic.Mlb.PitcherGameLog`, `SportsFanatic.Mlb.PlayerStatcast`, `SportsFanatic.Mlb.BatterVsPitcher`, `SportsFanatic.Mlb.GameWeatherForecast` — check `lib/sports_fanatic/mlb/` first; only add what's missing.
   - Extend (if missing): `SportsFanatic.Mlb.Game` adds `:away_starter_mlb_id`, `:home_starter_mlb_id`; `SportsFanatic.Mlb.PlayerBoxscore` adds `:is_home`.
3. **External API clients** in `lib/sports_fanatic/external_apis/`:
   - `mlb_stats.ex` — `fetch_schedule/1`, `fetch_boxscore/1`, `fetch_pitcher_season_stats/2`, `fetch_player_statcast/2`, `fetch_batter_vs_pitcher/3`, `lookup_player/1`. Single retry on transient error; 50 ms throttle.
   - `open_meteo.ex` — `fetch_forecast/4`, `fetch_archive/3`, `extract_at_game_time/2`. Free tier (no key); supports `OPENMETEO_API_KEY` when set.
4. **Helpers**:
   - `SportsFanatic.Predictions.Stadiums` — port `lib/stadiums.py` venue → (lat, lon) lookup.
   - `SportsFanatic.Predictions.ParkFactors` — DEFAULT_PARK_HIT_FACTORS map + DB lookup with fallback to 1.0.

## Phase 2 — Feature engineering & Inference

5. **Feature engineering** (`lib/sports_fanatic/predictions/`):
   - `features.ex` — `@feature_cols`, `build_inference_row/3`, `build_training_rows/2`. SQL aggregations via `Repo.query!` for rolling stats (per architect note §Notes for Downstream Agents).
   - `feature_loader.ex` — DB query helpers that produce maps consumed by Features.
6. **Inference client** (`predictions/inference.ex`):
   - `score/2` calls `http://python-bridge:8000/inference/hit` via Req with 120 s timeout; goes through existing circuit breaker.

## Phase 3 — Python helper

7. **Python `/inference/hit`** in `python_bridge/src/api/inference.py`:
   - Fits `GradientBoostingClassifier` on training rows; predicts on inference rows.
   - Returns `{model_version, training_metrics, predictions: [{player_mlb_id, hit_prob, prediction}]}`.
   - Reject payloads > 25 MB; validate schema with Pydantic.
   - Wire into `python_bridge/src/main.py` router list.

## Phase 4 — Workers (Oban)

All in `lib/sports_fanatic/workers/`, queue `:predictions`, `max_attempts: 3`, `unique: [period: 3600]`.

8. `FetchScheduleWorker` — verify/extend existing to write `away_starter_mlb_id` / `home_starter_mlb_id` and venue.
9. `FetchLineupsWorker` — remove chained `GeneratePredictionsWorker.new(...)` call (orchestrator now drives sequencing).
10. `FetchPitcherStatsWorker` — `Task.async_stream` with `pitcher_stats_concurrency` (default 4); skip pitchers fresh < 24 h.
11. `FetchBvPWorker` — `Task.async_stream` with `bvp_concurrency` (default 6).
12. `SeedPitcherHistoryWorker` — back-fills last 30 days of games; `Task.async_stream` with `seed_pitcher_concurrency` (default 4).
13. `SeedStatcastWorker` — pulls Baseball Savant aggregates for today's hitters; `Task.async_stream` with `statcast_concurrency` (default 4).
14. `ForecastWeatherWorker` — per-venue Open-Meteo lookup; `weather_concurrency` (default 8).
15. `PredictHitsWorker` — assembles training + inference rows, calls `Inference.score/2`, upserts `mlb.hit_predictions`, invalidates cache, broadcasts PubSub.
16. `DailyHitPredictionsWorker` (orchestrator) — sequential at the step level, parallel internally. Opens `system.pipeline_runs` row, calls each step worker directly (not via `Oban.insert`) for synchronous chaining inside one job, records `system.pipeline_steps` per step.

## Phase 5 — Context API

17. **`SportsFanatic.Predictions`** context (`lib/sports_fanatic/predictions.ex`):
    - `list_for_date/2`, `get_for_player/2`, `list_today/0`, `list_runs/1`, `run_now/1`, `stream_player_results/1`.
    - Cache reads via `SportsFanatic.Cache` with `sf:data:hit_prediction:{player_mlb_id}:{date}` TTL 5 min.

## Phase 6 — Web layer

18. **Router** (`lib/sports_fanatic_web/router.ex`):
    - `live "/predictions", PredictionsLive, :index` in root browser scope.
    - 301 redirect for `/mlb/players` → `/predictions` via a small redirect controller or `Plug.Conn.redirect` in router.
    - Keep `/mlb/players/:team/:player` show route unchanged.
19. **`PredictionsLive`** (`lib/sports_fanatic_web/live/predictions_live.ex`):
    - Mount → assigns `predictions_date`, `predictions` (sorted desc by `hit_prob`), filters; subscribes to `"predictions:hits:{date}"`.
    - Card with hit % large, team logo, opponent, game time, batting order, position.
20. **Player detail** (`PlayerController.show/2` + `show.html.heex`):
    - Inject `<.today_hit_banner prediction={@today_hit_prediction} />` at top.
    - Controller assigns `@today_hit_prediction` from `Predictions.get_for_player/2`.
21. **Scouting** (`ScoutingController.show/2` and `ScoutingLive`):
    - On mount, fetch `Predictions.get_for_player/2` for today; cache under `sf:data:hit_prediction:*`.
    - Render rich banner: matchup, game time, ballpark, hit %, probable pitcher, weather one-liner.
22. **Layout** (`root.html.heex`):
    - Rename desktop and mobile nav `Players` → `Predictions`; href `/predictions`.

## Phase 7 — Admin (Joshua)

23. **`AdminLive`** adds `:predictions` tab to the existing tab switcher:
    - Header: `hit_predictions_enabled` toggle, cron input, concurrency input, "Run Now" button.
    - Run history: last 30 rows from `system.pipeline_runs WHERE pipeline_type = 'hit_predict_daily'`.
    - Per-run drill-down: `mlb.hit_predictions` for `pipeline_run_id` sorted by hit_prob desc.
    - Events: `switch_tab` ("predictions"), `toggle_predictions_flag`, `set_predictions_cron`, `set_predictions_concurrency`, `run_predictions_now`, `view_run`.

## Phase 8 — Config / runtime

24. **`config/config.exs`**:
    - Oban queues: add `predictions: 4`.
    - Oban crontab: add `DailyHitPredictionsWorker` with cron loaded from runtime.
25. **`config/runtime.exs`**:
    - `config :sports_fanatic, :predictions, ...` block per spec §Config Additions.
26. **`.env.example` and `.env`**:
    - Add the new predictions vars + `OPENMETEO_API_KEY` (blank acceptable).
27. **`docker-compose.yml`**:
    - Pass new env vars to `web` and `python-bridge` services (where relevant).

## Phase 9 — Python bridge cleanup

28. Delete (in worktree) endpoints superseded by Elixir:
    - `python_bridge/src/api/predict.py`
    - `python_bridge/src/api/schedule.py` (if it exists)
    - Monte-carlo / `/simulation/run` (if no callers — grep `lib/`).
    - `/scouting/search_multi`, `/scouting/classify` (if exist).
    - `/agents/execute` stub.
29. Remove from `lib/sports_fanatic/python_bridge.ex`:
    - `predict_hits/1`, `predict_hrs/1`, `fetch_schedule/1`, `fetch_mlb_teams/0`, `fetch_roster/1`, `run_simulation/2`, `search_player_multi/1`, `classify_content/2`, `execute_agents/2`.
30. Update `python_bridge/src/main.py` to register only the remaining routers + new `/inference/hit`.

## Phase 10 — Tests, docs, build

31. **Unit tests** (`mix test.unit`):
    - `HitPrediction` changeset validates required fields, bounds on `hit_prob` (0.0–1.0), enum values for `prediction`.
    - `Features` synthetic-input unit tests (no DB) for any pure helpers.
    - `OpenMeteo.extract_at_game_time/2` parses hourly maps correctly.
    - `MlbStats` parsing helpers on captured JSON fixtures.
    - `Predictions` context with a stubbed `Inference` module via `Application.put_env`.
    - `DailyHitPredictionsWorker` arg parsing & feature-flag gate.
32. **Integration tests** (`mix test`):
    - `/predictions` LiveView renders sorted cards on a seeded DB.
    - `/mlb/players` returns 301 to `/predictions`.
    - Admin Predictions tab renders, toggles flag, enqueues a Run Now.
    - Migrations apply cleanly on a fresh DB.
33. **Docs**:
    - Append a "Hit Predictions Pipeline" section to `CLAUDE.md` documenting workers, routes, env vars, admin tab.
    - Document `.env` additions in CLAUDE.md "Environment variables" table.
34. **Build**:
    - `mix format` and `mix compile --warnings-as-errors` must pass.
    - `mix assets.build` should still succeed (no JS changes needed for this iteration).

---

## Dependencies between phases

- Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5 → Phase 6 / Phase 7 (parallelizable) → Phase 8 → Phase 9 → Phase 10.
- Inside Phase 6, the LiveView and the scouting/player banners are independent and can be implemented in either order.

## Acceptance gate

Spec §Acceptance Criteria (lines 770–822 of `architect.md`) is the final checklist. Coder + Tester + Reviewer all reference that list.

## Risk register

- **Python `/inference/hit` payload size** — limit training-rows lookback to last 3 seasons; if it exceeds ~25 MB, page in smaller batches.
- **MLB Stats API rate-limit** — `Task.async_stream` keeps total throughput bounded by concurrency; in the wild this has proven safe at 4–8 concurrent requests.
- **Distributed double-run** — Oban `unique: [period: 3600]` + `mlb.hit_predictions (prediction_date, player_mlb_id)` unique index. Verified by acceptance criterion §Multi-container.
- **EDT/EST drift** — admin cron override is exposed; default `0 12 * * *` is correct for the May 2026 EDT season.

## Out of scope (do not touch)

- News pipeline, chatbot, legacy agent settings system.
- HR prediction port (separate future spec).
- Native Elixir GBT inference (future ADR-001 follow-up).
- Bet resolution back-fill (columns reserved, worker not built).
