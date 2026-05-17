# Build Agent Notes

## Summary

Verified build configuration for the Agentic News Feed feature. Ran `mix compile --warnings-as-errors` and `mix format --check-formatted` against the worktree, audited `config/config.exs`, `mix.exs`, `python_bridge/requirements.txt`, and the `test.unit` alias. No new Elixir dependencies were added. The Python bridge `requirements.txt` is unchanged. Three files fail the formatter check.

## Decisions

- No Makefile or CI changes were made; task was verification only, with changes prohibited unless a build failure was found. The format failures are reported below but are not build failures (they do not block `mix compile`).

## Files Reviewed

- `mix.exs` — no new deps; `test.unit` alias correctly includes all 4 new test file paths
- `config/config.exs` — `RunNewsAgentsWorker` crontab entry is present and correct
- `python_bridge/requirements.txt` — unchanged; no new Python packages needed
- `python_bridge/src/agents/parser.py` — new, correct
- `python_bridge/src/api/agents.py` — new, correct
- `python_bridge/src/main.py` — agents router registered at `/agents`
- `python_bridge/src/news/models.py` — `domain_tags` field added to `NewsAnalysis`
- `lib/sports_fanatic/workers/run_news_agents_worker.ex` — cron at `0 13 * * *`, queue `content_generation`, `max_attempts: 3`
- `lib/sports_fanatic/workers/parse_setting_worker.ex` — queue `content_generation`, `max_attempts: 3`
- `lib/sports_fanatic/agents.ex` — context module reviewed; one potential nil issue noted below
- `priv/repo/migrations/20260515190000_create_news_agent_tables.exs` — migration reviewed, structurally correct

## CI Pipeline

No changes made to CI pipeline. Existing pipeline applies.

## Issues Found

### [MEDIUM] mix format --check-formatted: 3 files not formatted

`mix format --check-formatted` exits with code 1. Three files have lines exceeding the default 98-character print width:

1. `lib/sports_fanatic/workers/parse_setting_worker.ex` line 53 — `Logger.error(...)` call too long
2. `test/sports_fanatic/content/news_item_domain_tags_test.exs` lines 37, 52, 84 — long assert/variable lines
3. `lib/sports_fanatic_web/live/news_live.ex` line 258 — long `put_flash(...)` call

These are not compiler errors and do not block the build. They will fail any CI step that runs `mix format --check-formatted`. Run `mix format` in the worktree to fix all three automatically.

### [LOW] Potential nil return from count_user_settings_last_hour/1

`Agents.count_user_settings_last_hour/1` uses `select([s], count(s.id)) |> Repo.one()`. `Repo.one/1` returns `nil` when no rows exist, but `count()` in a non-grouped aggregate always returns a row (returning 0 when empty), so in practice this returns an integer. However, the call site compares the result with `>=` without a nil guard. If the query were ever refactored or the DB returned nil unexpectedly, this would raise a `FunctionClauseError`. Low risk given the current query, but `Repo.one!()` or an explicit `|| 0` fallback would be safer.

### [LOW] FetchNewsWorker `* * * * *` cron vs CLAUDE.md documentation mismatch

`config/config.exs` shows `FetchNewsWorker` on `*/15 * * * *` (every 15 minutes). The CLAUDE.md documentation says it runs every 1 minute on `* * * * *`. This is a pre-existing discrepancy unrelated to this feature, but worth noting for documentation accuracy.

### [INFO] Python bridge requirements.txt unchanged

No new Python packages were added for the agents feature. The parser uses `anthropic` which is already pinned at `0.34.0`. No action needed.

### [INFO] No new mix.exs dependencies

The feature does not introduce new Elixir hex packages. No lockfile update is required beyond what the existing deps cover.

## Recommendations for Next Agent

- Run `mix format` in the worktree before merging. The three formatting failures will block any CI pipeline step that runs `mix format --check-formatted`. This is a one-command fix.
- The `count_user_settings_last_hour/1` nil guard is low risk but worth hardening with `|| 0` at the call site in `create_setting/2` if the team prefers defensive coding.
- Integration tests for `Agents.create_setting/2` (including the hourly rate limit path) require a live database; they are currently absent and should be added when Docker is available.
