# Coding Agent Notes

## Summary
Implemented the Agentic News Feed feature across Elixir/Phoenix backend and Python FastAPI bridge. Created database migration, Ecto schemas, context module, two Oban workers, Python Bridge endpoints, and updated the NewsLive LiveView with command input, tab switching, entity display, and search filtering. Updated the admin panel with an Agents tab for feature flag control and manual triggering.

## Decisions
- Used `session["session_token"]` in LiveView mount to load current_user, matching the existing FetchCurrentUser plug pattern
- Kept the `unless` gate pattern as a simple `if/else` in RunNewsAgentsWorker to avoid the Elixir `unless` non-short-circuit issue
- Used `or_where` in RunNewsAgentsWorker for player/team text matching since we don't have direct joins from parsed criteria to entity IDs yet (Phase 1 limitation)
- Added `league` field to team data in `News.build_feed/1` to support league badges in the template
- Did NOT add Jido dependency -- spec says Phase 2 for Jido framework integration
- The `execute_agents` Python endpoint is a Phase 2 stub returning empty results

## Files Modified
- `priv/repo/migrations/20260515190000_create_news_agent_tables.exs` -- New migration
- `lib/sports_fanatic/agents/news_agent_setting.ex` -- New schema
- `lib/sports_fanatic/agents/news_agent_result.ex` -- New schema
- `lib/sports_fanatic/agents.ex` -- New context module
- `lib/sports_fanatic/content/news_item.ex` -- Added domain_tags field
- `lib/sports_fanatic/python_bridge.ex` -- Added parse_setting/2, execute_agents/2
- `python_bridge/src/agents/__init__.py` -- New empty module
- `python_bridge/src/agents/parser.py` -- New Claude Haiku parser
- `python_bridge/src/api/agents.py` -- New FastAPI router
- `python_bridge/src/main.py` -- Registered agents router
- `python_bridge/src/news/analyzer.py` -- Added domain_tags to classification
- `python_bridge/src/news/models.py` -- Added domain_tags to Pydantic model
- `lib/sports_fanatic/workers/parse_setting_worker.ex` -- New async parsing worker
- `lib/sports_fanatic/workers/run_news_agents_worker.ex` -- New daily execution worker
- `config/config.exs` -- Added RunNewsAgentsWorker to Oban crontab
- `lib/sports_fanatic/workers/fetch_news_worker.ex` -- Store domain_tags from AI
- `lib/sports_fanatic/news.ex` -- Added domain_tags and league to feed data
- `lib/sports_fanatic_web/live/news_live.ex` -- Full rewrite with command input, tabs, search
- `lib/sports_fanatic_web/live/news_live.html.heex` -- Full rewrite with UI components
- `lib/sports_fanatic_web/live/admin_live.ex` -- Added Agents tab

## Issues Found
- [INFO] The RunNewsAgentsWorker uses ILIKE text matching for players/teams which is a Phase 1 simplification. Phase 2 should use player_ids/team_ids direct matching via parsed entity resolution.

## Recommendations for Next Agent
- Test the migration runs cleanly against a PostgreSQL instance
- Verify the LiveView renders correctly for both authenticated and unauthenticated users
- Test the /settings-apply and /settings-clear command flows end-to-end
- Verify PubSub broadcasts update the UI when ParseSettingWorker completes
- Test that the search filter works with debounce and clears properly
- Verify the admin Agents tab loads settings and the toggle/manual trigger work
- Check that existing unit tests still pass (verified: 295 tests, 0 failures)
- The Python Bridge endpoints need testing with the actual Claude API

## Remediation (Retry 1)
### Feedback Addressed
- SEC-NEW-001 (HIGH): Internal error details exposed in ParseSettingWorker error_message -> Replaced `inspect(reason)` in user-facing error_message with generic "Unable to parse your setting. Please try again later." Detailed error now logged via Logger.error instead.
- SEC-NEW-002 (HIGH): Missing hourly rate limit on /settings-apply -> Added `count_user_settings_last_hour/1` query in Agents context using `ago(1, "hour")`. `create_setting/2` now checks hourly count first (limit: 5/hour) before the max-settings check. LiveView handles `:hourly_rate_limit_exceeded` with appropriate flash message.
- SEC-NEW-003 (MEDIUM): Missing validate_required(:status) in update_changeset -> Added `|> validate_required([:status])` to `NewsAgentSetting.update_changeset/2`.
- SEC-NEW-006 (LOW): Float.round/2 crash on integer confidence -> Changed `Float.round(confidence * 100, 0)` to `Float.round((confidence + 0.0) * 100, 0)` which coerces integer to float before the call.

### Unresolved
- None. All four findings addressed.
