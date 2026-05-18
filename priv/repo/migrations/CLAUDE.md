Parent: `../../../CLAUDE.md`

# CLAUDE.md — Database Migrations & Schemas

> See the Documentation Placement Rule in `../../../CLAUDE.md` before adding
> content here.

---

Six PostgreSQL schemas. All UUIDs use `gen_random_uuid()`. Migrations use
`prefix: "<schema>"` everywhere.

| Schema | Tables |
|--------|--------|
| `public` | sports, teams, players, venues |
| `mlb` | games, scheduled_games, lineups, player_boxscores, player_season_stats, picks, hr_picks, game_weather, park_hr_factors |
| `content` | scouting_reports, game_day_magazines, news_items, sitemaps, injury_reports, team_magazines |
| `accounts` | users, subscriptions, sessions, news_agent_settings, news_agent_results, chat_sessions, chat_messages, query_clusters, query_cluster_members, x_credentials, x_watched_targets |
| `system` | pipeline_runs, pipeline_run_events, pipeline_steps, cache_invalidations, feature_flags, x_posts, x_api_calls, x_post_rotation |
| `scouting` | (from sports-fan-agent, retained) |

## Conventions

- File name: `YYYYMMDDHHMMSS_<verb>_<subject>.exs`. Use UTC.
- Module name: `SportsFanatic.Repo.Migrations.<CamelCase>`.
- Tables created with `prefix: "<schema>"` and `primary_key: false`.
- PKs: `add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")`.
- FKs to public schema use `references(..., type: :binary_id, prefix: "public")`.
- Timestamps: `timestamps(type: :utc_datetime)`.
- CHECK constraints for enums use raw SQL via `execute(up_sql, down_sql)`.

## Recent migrations (chronological)

| File | Purpose |
|------|---------|
| `20260419000001_create_accounts_schema.exs` | users, sessions, subscriptions |
| `20260419000002_create_public_tables.exs` | sports, teams, players, venues |
| `20260419000003_create_mlb_schema.exs` | games, scheduled_games, lineups, picks |
| `20260419000004_create_content_schema.exs` | news_items, scouting_reports, gameday |
| `20260419000005_create_system_schema.exs` | pipeline_runs, cache_invalidations |
| `20260502034000_add_ai_fields_to_news_items.exs` | sentiment, ai_summary |
| `20260502090000_add_player_id_to_lineups.exs` | UUID FK on lineups |
| `20260502111530_create_feature_flags.exs` | system.feature_flags |
| `20260502120000_create_scouting_pipeline_tables.exs` | pipeline + steps |
| `20260502140200_add_content_text_to_player_source_urls.exs` | source URL body |
| `20260502143000_add_player_name_to_lineups.exs` | denormalized for speed |
| `20260503083207_add_digest_to_player_source_urls.exs` | dedup digest |
| `20260503112414_add_injury_area_grade_to_news_items.exs` | injury_area, injury_grade |
| `20260511183200_add_oban_tables.exs` | Oban schema |
| `20260515190000_create_news_agent_tables.exs` | agent settings + results |
| `20260516100000_create_chat_tables.exs` | chat sessions, messages, clusters |
| `20260516100001_add_news_items_search_vector.exs` | tsvector + GIN + Exa URL unique |
| `20260516130000_create_user_feeds.exs` | user-imported feeds |
| `20260518100000_create_x_credentials.exs` | X OAuth credentials (singleton) |
| `20260518100001_create_x_posts.exs` | X tweets table |
| `20260518100002_create_x_watched_targets.exs` | accounts to watch |
| `20260518100003_create_x_api_calls.exs` | audit log per X write |
| `20260518100004_create_x_post_rotation.exs` | daily rotation + plan |
| `20260518100005_create_injury_reports.exs` | per-player daily injury page |
| `20260518100006_create_team_magazines.exs` | per-team daily magazine |
| `20260518100007_seed_x_agent_feature_flags.exs` | x_agent_enabled etc. |
| `20260518200001_create_pipeline_run_events.exs` | system.pipeline_run_events (streaming progress) |
| `20260518200002_add_run_kind_to_pipeline_runs.exs` | run_kind, seed dates, checkpoint, current_step on pipeline_runs |

## Specific table notes

### `content.news_items`

- Injury data lives in `category` enum (`injury_new`, `injury_worsening`,
  `injury_update`, `injury_recovery`, `injury_cleared`) plus
  `injury_area :string` (free text) and `injury_grade :string` (enum:
  `day_to_day`, `10_day_il`, `15_day_il`, `60_day_il`, `season_ending`,
  `pending_imaging`, `cleared`, `rehab_assignment`, `unknown`). **Not** in
  `domain_tags`.
- `domain_tags TEXT[] DEFAULT '{}'` + GIN index — populated by
  `FetchNewsWorker`.
- `search_vector tsvector GENERATED ALWAYS AS (...)` + GIN — weighted title
  (A), ai_summary (B), body (C).
- Partial unique index on `(source_url) WHERE source = 'exa' AND
  source_url IS NOT NULL` enforces Exa dedup.

### `accounts.x_credentials` (singleton)

Singleton enforced via `singleton :boolean default true NOT NULL` column with
`UNIQUE` index on `(singleton)`. Exactly one row. OAuth upserts overwrite.

Encryption: AES-256-GCM ciphertext + IV per token, encoded as `:binary`
columns. Plaintext is never persisted; the key comes from
`X_TOKEN_ENCRYPTION_KEY`. See `lib/sports_fanatic/x/CLAUDE.md` for details.

### `system.x_posts`

CHECK constraints (raw SQL):

```sql
status IN ('pending','approved','posted','failed','rejected','cancelled')
post_type IN ('top_hits','injury','team_magazine','scorecard','reply')
```

`cost_mills :integer` is tenths of a cent (15 mills = $0.015, 200 mills =
$0.20).

### `mlb.lineups`

Has both `player_nerds_id :integer` (older) and `player_id :binary_id`
(UUID FK, newer). Older rows may have nil `player_id`. The "in today's
lineup" predicate prefers the UUID match and falls back to nerds id.

## Adding a migration

1. Generate with `mix ecto.gen.migration <name>` or pick a UTC timestamp.
2. Use `prefix: "<schema>"` on every `table/3` and `index/2` call.
3. For enum columns, add a CHECK constraint via `execute/2` so both up and
   down work cleanly.
4. Add an entry to the table above.
5. If the new table is referenced by a new context, add a doc bullet in the
   relevant context's CLAUDE.md.

## Restoring from a backup

See `scripts/CLAUDE.md` for `db_backup.sh` / `db_restore.sh` flags. The init
SQL lives in `priv/repo/init.sql`.
