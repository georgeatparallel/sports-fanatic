Parent: `../../../CLAUDE.md`

# CLAUDE.md — Oban Workers

> See the Documentation Placement Rule in `../../../CLAUDE.md` before adding
> content here.

---

All workers live here. They use `use Oban.Worker, queue: :<queue>,
max_attempts: <n>` and implement `perform/1`. Cron schedules are defined in
`config/config.exs` under `Oban.crontab`. Times are UTC unless otherwise noted.

## Queues (from `config/config.exs`)

| Queue | Concurrency | Used by |
|-------|-------------|---------|
| `default` | 10 | most workers |
| `data_fetch` | 5 | Fetch* workers |
| `content_generation` | 3 | Generate* workers |
| `cache` | 2 | WarmCache, sitemap |
| `system` | 1 | Cleanup |
| `x_agent` | 2 | X agent workers (see below) |

## Schedule (cron)

| Worker | Cron | Notes |
|--------|------|-------|
| `FetchScheduleWorker` | `0 6 * * *` | Daily MLB schedule. On success: `Cache.del_pattern("sf:data:game_card:player:*:{date}")` to invalidate per-player game cards. |
| `FetchLineupsWorker` | `*/30 8-20 * * *` | Every 30 min during gameday window. On success: invalidates `sf:page:players:{date}` AND `sf:data:game_card:player:*:{date}`. |
| `FetchNewsWorker` | `*/15 * * * *` | Every 15 minutes (S3 + Python Bridge classify) |
| `GenerateScoutingWorker` | `0 7 * * *` | Daily AI scouting — invalidates `sf:page:scouting:{team}:{slug}` per player on success |
| `GenerateGameDayWorker` | `0 9 * * *` | Daily Game Day Magazines |
| `GenerateSitemapWorker` | `0 */6 * * *` | Sitemap regeneration |
| `CleanupWorker` | `0 3 * * *` | Daily housekeeping |
| `GeneratePlayerSeoWorker` | `0 4 * * *` | Daily player SEO refresh |
| `GeneratePredictionsWorker` | `30 9 * * *` | Daily ML hit/HR predictions |
| `WarmCacheWorker` | `*/15 * * * *` | Pre-warm Valkey |
| `RunNewsAgentsWorker` | `0 13 * * *` | 9 AM ET daily — news agent settings |
| `ConsolidateQueriesWorker` | `0 * * * *` | Hourly chat query clustering |
| `ScheduledExaSearchWorker` | `0 14 * * *` | Daily Exa search per cluster |
| `FeedResearchWorker` | `0 13 * * *` | Daily feed item research |
| `XPostSchedulerWorker` | `30 15 * * *` | 11:30 ET (EDT) — plan day's X posts |
| `RefreshXTokenWorker` | `0 * * * *` | Hourly X OAuth token refresh |
| `OutboundReplyWorker` | `*/30 16-2 * * *` | Every 30 min during ~12:00–22:00 ET (EDT) |
| `WeeklyScorecardWorker` | `0 14 * * 0` | Sunday 10:00 ET (EDT) — weekly thread |

## Game-card cache invalidation

Four workers — `FetchScheduleWorker`, `FetchLineupsWorker`,
`FetchPitcherStatsWorker`, `ForecastWeatherWorker` — each end their
success path with
`Cache.del_pattern("sf:data:game_card:player:*:#{YYYY-MM-DD}")` to
invalidate the per-player "today's scheduled game" card surfaced on the
scouting and player pages by `SportsFanatic.Mlb.todays_game_for_player/2`.

The wildcard is the player UUID — one DEL per worker run, not per player.
All four hooks are wrapped in `try/rescue` so a Valkey outage cannot fail
the underlying job.

## Non-cron (on-demand)

- `GenerateScoutingOnDemandWorker` — on-demand scouting report generation (Claude path); invalidates `sf:page:scouting:{team}:{slug}` on success.
- `ParseSettingWorker` — enqueued by `Agents.create_setting/2`.
- `MainPostWorker` — enqueued by `XPostSchedulerWorker` at jittered times.
- `EngagementWatcherWorker` — enqueued recursively by `MainPostWorker` and
  itself (18 iterations × 5 min).
- `InitialSeedWorker` — enqueued by `SportsFanatic.Predictions.start_initial_seed/0`
  from the admin Predictions tab. `max_attempts: 5`, `unique` on
  `{seed_from, seed_through}`. Date-by-date backfill with per-date
  checkpoint. See `lib/sports_fanatic/predictions/CLAUDE.md`.

## CleanupWorker steps

`CleanupWorker` (3 AM ET daily) runs:

1. `Accounts.delete_expired_sessions/0` — purges expired user sessions.
2. Prunes `system.pipeline_run_events` rows older than 7 days (retention
   for streaming progress events from
   `SportsFanatic.Predictions.Progress`).

## Enqueueing from IEx

```elixir
%{} |> SportsFanatic.Workers.FetchLineupsWorker.new() |> Oban.insert()
%{"setting_id" => "uuid"} |> SportsFanatic.Workers.ParseSettingWorker.new() |> Oban.insert()
%{} |> SportsFanatic.Workers.XPostSchedulerWorker.new() |> Oban.insert()
%{"post_id" => "uuid", "post_type" => "top_hits"}
|> SportsFanatic.Workers.MainPostWorker.new()
|> Oban.insert()
```

## Adding a new worker

1. Create `lib/sports_fanatic/workers/my_worker.ex` with `use Oban.Worker`.
2. Add to crontab in `config/config.exs` if scheduled.
3. Gate on a feature flag if the work is risky / external — check
   `FeatureFlags.enabled?("my_flag")` at the top of `perform/1` and return
   `{:ok, :disabled}` when off.
4. Add to `lib/sports_fanatic/application.ex` supervision **only** if it needs
   startup configuration (most workers don't).
5. Add a test file under `test/sports_fanatic/workers/` and add it to the
   `unit_test_files` block in `mix.exs` if it doesn't touch Postgres.

## X agent worker family

See `lib/sports_fanatic/x/CLAUDE.md` for the per-worker contract, posting
funnel, jitter algorithm, and approval-queue interaction.
