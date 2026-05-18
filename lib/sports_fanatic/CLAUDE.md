Parent: `../../CLAUDE.md`

# CLAUDE.md — `lib/sports_fanatic/`

> See the Documentation Placement Rule in `../../CLAUDE.md` before adding
> content here.

---

The main Elixir application namespace. Contexts live at the top level; schemas
under typed sub-folders.

## File layout

```
lib/sports_fanatic/
  accounts/           User, Session Ecto schemas
  accounts.ex         Accounts context (register, authenticate, session CRUD)
  agents.ex           News-agent context (legacy daily settings)
  agents/             See agents/CLAUDE.md
  ai/                 Direct Anthropic Elixir-side helpers (kept thin)
  billing/            Subscription schema
  billing.ex          Stripe webhook handlers (checkout, invoice, subscription)
  cache.ex            Valkey wrapper — get/set/delete/invalidate_pattern + TTL constants
  chat_bot.ex         ChatBot context (session CRUD, rate limiting, clusters)
  chat_bot/           See chat_bot/CLAUDE.md
  content/            ScoutingReport, GameDayMagazine, NewsItem, Sitemap,
                       InjuryReport, TeamMagazine schemas
  date_helper.ex      today_eastern/0 etc.
  external_apis/      Exa, FantasyNerds clients (Req-based) — see external_apis/CLAUDE.md
  feature_flags.ex    FeatureFlags context — ETS-cached, 30s TTL
  feature_flags/      feature_flag.ex schema (system.feature_flags)
  feeds/              CSV feed import schemas + research worker
  feeds.ex            Feeds context (RSS/CSV import)
  joshua_auth.ex      Passphrase admin gate helper
  mlb/                Sport, Team, Player, Venue, Game, ScheduledGame, Lineup,
                       Pick, HrPick schemas
  mlb.ex              MLB context — todays_game_for_player/2 (game card sourced
                       from mlb.scheduled_games, joined to teams by name)
  news.ex             News context — cached feed reads, entity resolved list
  news/               entity_matcher.ex — fuzzy player/team matching
  python_bridge.ex    HTTP client for Python bridge with circuit breaker
  python_bridge/      CircuitBreaker GenServer + HealthCheck GenServer
  scouting.ex         Scouting context
  scouting/           ScoutingReport, generation pipeline
  storage.ex          S3 storage — put_object/3, get_object/2, sanitize_key/1
  x.ex                X (Twitter) context — OAuth, post_tweet/2, spend
  x/                  See x/CLAUDE.md
  workers/            See workers/CLAUDE.md
```

## Valkey caching

`SportsFanatic.Cache` wraps Redix. Key prefixes:

```
sf:page:player:{team}:{slug}        TTL 5 min
sf:page:team:{slug}                 TTL 10 min
sf:page:lineup:today                TTL 2 min
sf:page:lineup:{past-date}          TTL 24 hours
sf:page:news:{date}:{slug}          TTL 5 min
sf:page:scouting:{team}:{slug}      TTL 15 min — invalidated on success by GenerateScoutingWorker AND GenerateScoutingOnDemandWorker (via invalidate_scouting_page/1) in addition to Pipeline.process_single_player/3
sf:page:gameday:{date}:{slug}       TTL 10 min
sf:page:injury:{slug}:{date}        TTL 60 min
sf:page:team-magazine:{slug}:{date} TTL 30 min
sf:page:players:{YYYY-MM-DD}        TTL until next Eastern midnight (floor 600 s, cap 86_400 s) — full anonymous HTML for /mlb/lineups/:date
sf:data:players:roster              TTL 24 h — slim roster blob for search dropdown (all players)
sf:data:player:card:{mlb_id}        TTL 6 h  — per-card render data (badge, link target); mlb_id is integer or player UUID fallback
sf:data:game_card:player:{uuid}:{YYYY-MM-DD}
                                    TTL until next Eastern midnight — per-player "today's scheduled game" card
                                    (opponent, time, venue, probable pitcher, weather). `"__none__"` literal cached
                                    on off-days so we don't query Postgres every request for a non-playing player.
                                    Invalidated on success by FetchScheduleWorker, FetchLineupsWorker,
                                    FetchPitcherStatsWorker, ForecastWeatherWorker via
                                    `Cache.del_pattern("sf:data:game_card:player:*:{YYYY-MM-DD}")`.
sf:data:predictions:*               TTL 5 min
sf:data:news:feed:{date}            TTL 60 s
sf:sitemap:*                        TTL 6 hours
```

Use `SportsFanatic.Cache.get/1`, `set/3`, `del/1`, `del_pattern/1`.
Key builders: `Cache.news_feed_key/1` accepts `%Date{}` or ISO-8601 string;
`Cache.players_page_key/1`, `Cache.players_roster_key/0`,
`Cache.player_card_key/1` for the Players page. `Cache.game_card_key/2` for
the per-player today's-game card (accepts a player UUID + `%Date{}` or ISO string).

## Storage (S3)

`SportsFanatic.Storage` wraps `ExAws.S3`. Useful helpers:

- `put_object/3`, `get_object/2`
- `news_article_key/2` — date-partitioned key `news/raw/{YYYY}/{MM}/{DD}/{id}.json`
- `sanitize_key/1` — strips anything outside `[a-zA-Z0-9_-]`. **Always**
  sanitize external identifiers before composing S3 keys or filesystem paths.

Env vars: `NEWS_S3_BUCKET`, `NEWS_S3_ENABLED`, `AWS_REGION`,
`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`. When `NEWS_S3_ENABLED=false`,
uploads are skipped but PostgreSQL inserts still succeed (`s3_key` = nil).

## Adding a new context

1. Create `lib/sports_fanatic/<area>.ex` with `@moduledoc`, public-API typespecs.
2. Schemas under `lib/sports_fanatic/<area>/`.
3. Migrations under `priv/repo/migrations/` (see `priv/repo/migrations/CLAUDE.md`).
4. Tests under `test/sports_fanatic/<area>/`.
5. Unit tests are pure (no Postgres) when possible — add to the `unit_test_files`
   block in `mix.exs`.

## Anti-patterns to avoid

- Direct `Repo` calls from controllers — go through the context module.
- String interpolation into Ecto queries (always use pinned variables).
- Calling `raw/1` on any external/LLM string. Use `Phoenix.HTML.html_escape/1`
  or `HtmlSanitizeEx.strip_tags/1` at the storage boundary.
- New compile-time `Application.get_env/2` — prefer `runtime.exs` and read at
  GenServer init or per-call.
