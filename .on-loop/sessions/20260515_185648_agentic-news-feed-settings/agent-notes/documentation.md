# Documentation Agent Notes

## Summary

Updated the project's CLAUDE.md at the worktree root (`/Users/charmalloc/dev/sports-fanatic/.claude/worktrees/agentic-news-feed-settings/CLAUDE.md`) to document the Agentic News Feed feature implemented in this session.

## Decisions

- Added a top-level "Agents System" section immediately after "Project Purpose" so it is prominent and self-contained. This section covers command input, settings lifecycle, daily execution, admin config, and entity display — the five developer-facing behaviors that are new.
- Inserted LiveView events into the Routing Conventions section as a table, and documented the new `agent:settings:{user_id}` PubSub topic alongside the existing topics, so the routing section remains the single reference for all NewsLive interactions.
- Expanded the Database Schemas section with per-column tables for both new tables and the altered `news_items` column. This is more detailed than the existing schema entries but warranted given the JSONB fields and non-obvious constraints (e.g., generic error messages, domain tag values).
- Noted the Valkey caching decision explicitly (no new keys; agent data is read directly from PostgreSQL) to prevent future developers from searching for cache keys that do not exist.
- Added `AGENTS-001` through `AGENTS-003` to Known Issues and TODOs to document the Phase 1 simplifications (ILIKE matching, execute stub, missing domain_tags backfill) so they are not mistaken for bugs.
- Added Common Tasks entries for enabling/disabling agents, manual IEx triggering, adding Phase 2 Jido skills, and backfilling domain_tags.

## Files Modified

- `/Users/charmalloc/dev/sports-fanatic/.claude/worktrees/agentic-news-feed-settings/CLAUDE.md` — Added Agents System section; updated Architecture Summary, File Structure, Routing Conventions (LiveView events + PubSub topics), Database Schemas (two new tables + news_items alteration), Valkey Caching (note on no new keys), Python Bridge (two new endpoints), Oban Workers (RunNewsAgentsWorker cron + ParseSettingWorker), Known Issues (three new AGENTS entries), Common Tasks (four new entries)

## Issues Found

- [INFO] The CLAUDE.md test count in Testing Strategy ("63 pure unit tests") reflects the pre-feature state. The coding agent notes show 295 tests passing after this feature. The test count was not updated in CLAUDE.md as it will drift quickly; developers should rely on `mix test.unit` output rather than a hardcoded number in docs.

## Recommendations for Next Agent

- The Testing Strategy section could be expanded to cover agent-specific test patterns once integration tests are added for the Agents context and RunNewsAgentsWorker.
- If a README.md is created for this project, the Agents System section from CLAUDE.md would make a good basis for the "Features" section.
- The Python Bridge API design section in `architect.md` contains full request/response schemas for `/agents/parse-setting` and `/agents/execute` that could be extracted into an `API.md` reference if external consumers are anticipated.
